open! Hardcaml
open! Signal

module I = struct
  type 'a t = {
    clock: 'a;
    clear: 'a;
    rom_data: 'a [@bits 8];
    rom_valid:'a;
  }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t = {
    rom_addr: 'a [@bits 16];
    part1_result: 'a [@bits 64];
    part2_result: 'a [@bits 64];
    finished: 'a;
  }
  [@@deriving hardcaml]
end

module State = struct
  type t = 
    | Wait_rom
    | Parse_lower
    | Parse_upper
    | Setup_calc
    | Calc_loop
    | Wait_summers
    | Done
    [@@deriving sexp_of, compare, enumerate]

    let to_int = function
    | Wait_rom -> 0
    | Parse_lower -> 1
    | Parse_upper -> 2
    | Setup_calc -> 3
    | Calc_loop -> 4
    | Wait_summers -> 5
    | Done -> 6
end

let powers_of_10 = List.init 20 (fun i -> let v = Z.pow (Z.of_int 10) i in of_string (Z.format "%b" v) |> fun s -> uresize s 64)
let pow10 p = mux p powers_of_10

let create scope (i: Signal.t I.t) = 
  let open I in
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
  let state = Always.State_machine.create (module State) spec in

  let rom_addr = Always.Variable.reg spec ~enable:vdd ~width:16 in
  let part1 = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let part2 = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let finished_out = Always.Variable.reg spec ~enable:vdd ~width:1 in


  (* Parser variables: *)
  let state_width = 3 in
  let spec_reset_1 = Reg_spec.override spec ~clear_to:(of_int ~width:state_width (State.to_int State.Parse_lower)) in
  let next_state_after_wait = Always.Variable.reg spec_reset_1 ~enable:vdd ~width:state_width in
  let parsed_lower_bin = Always.Variable.reg spec ~enable:vdd ~width:128 in
  let parsed_upper_bin = Always.Variable.reg spec ~enable:vdd ~width:128 in
  let parsed_lower_bcd = Always.Variable.reg spec ~enable:vdd ~width:80 in
  let parsed_upper_bcd = Always.Variable.reg spec ~enable:vdd ~width:80 in
  let lower_digits = Always.Variable.reg spec ~enable:vdd ~width:6 in
  let upper_digits = Always.Variable.reg spec ~enable:vdd ~width:6 in

  (* Range iter: *)
  let current_range_start = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let current_range_end = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let current_d = Always.Variable.reg spec ~enable:vdd ~width:6 in
  let calc_start = Always.Variable.reg spec ~enable:vdd ~width:1 in

  (* Summer inputs: *)
  let calc_d = Always.Variable.reg spec ~enable:vdd ~width:5 in
  let calc_range_start = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let calc_range_end = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let calc_lower_bcd = Always.Variable.reg spec ~enable:vdd ~width:80 in
  let calc_upper_bcd = Always.Variable.reg spec ~enable:vdd ~width:80 in

  let rom_addr_val = Always.Variable.value rom_addr in
  let parsed_lower_bin_val = Always.Variable.value parsed_lower_bin in
  let parsed_upper_bin_val = Always.Variable.value parsed_upper_bin in
  let parsed_lower_bcd_val = Always.Variable.value parsed_lower_bcd in
  let parsed_upper_bcd_val = Always.Variable.value parsed_upper_bcd in
  let lower_digits_val = Always.Variable.value lower_digits in
  let upper_digits_val = Always.Variable.value upper_digits in
  let next_state_val = Always.Variable.value next_state_after_wait in
  let current_range_start_val = Always.Variable.value current_range_start in
  let current_range_end_val = Always.Variable.value current_range_end in
  let current_d_val = Always.Variable.value current_d in
  let calc_start_val = Always.Variable.value calc_start in
  let part1_val = Always.Variable.value part1 in
  let part2_val = Always.Variable.value part2 in

  (* Helper signals: *)
  let ascii_0 = of_int ~width:8 (Char.code '0') in
  let ascii_9 = of_int ~width:8 (Char.code '9') in
  let ascii_hyphen = of_int ~width:8 (Char.code '-') in
  let ascii_comma = of_int ~width:8 (Char.code ',') in
  let is_digit = i.rom_valid &: (i.rom_data >=: ascii_0) &: (i.rom_data <=: ascii_9) in
  let digit_val = uresize (i.rom_data -: ascii_0) 4 in
  let is_hyphen = i.rom_valid &: (i.rom_data ==: ascii_hyphen) in
  let is_comma = i.rom_valid &: (i.rom_data ==: ascii_comma) in

  (* Instantiate range summer *)
  let range_summer_start = calc_start_val in
  let range_summer_i = {
    Range_summer.I.clock = i.clock;
    clear = i.clear;
    start = range_summer_start;
    d = Always.Variable.value calc_d;
    range_start = Always.Variable.value calc_range_start;
    range_end = Always.Variable.value calc_range_end;
    parsed_lower_bcd = Always.Variable.value calc_lower_bcd;
    parsed_upper_bcd = Always.Variable.value calc_upper_bcd;
  } in
  let range_summer_o = Range_summer.create scope range_summer_i in
  let finished_summer = range_summer_o.finished in
  let chunk_sum_part1 = range_summer_o.part_1_sum_out in
  let chunk_sum_part2 = range_summer_o.sum_out in

  Always.(compile [
    state.switch [
      State.Wait_rom, [
        Always.switch next_state_val (
          List.mapi (fun idx s -> (
            of_int ~width:state_width idx, [state.set_next s])
            ) State.all
        )
      ];

      State.Parse_lower, [
        if_ (~: (i.rom_valid)) [
          state.set_next State.Done;
        ][
          if_ is_digit [
            parsed_lower_bin <-- (uresize (parsed_lower_bin_val *: (of_int ~width:128 10)) 128) +: uresize digit_val 128;
            parsed_lower_bcd <-- (sll parsed_lower_bcd_val 4) +: uresize digit_val 80;
            lower_digits <-- lower_digits_val +:. 1;
            next_state_after_wait <-- of_int ~width:state_width (State.to_int State.Parse_lower);
            state.set_next State.Wait_rom;
            rom_addr <-- rom_addr_val +:. 1;
          ][
            if_ is_hyphen [
                parsed_upper_bcd <--. 0;
                parsed_upper_bin <--. 0;
                upper_digits <--. 0;
                next_state_after_wait <-- of_int ~width:state_width (State.to_int State.Parse_upper);
                state.set_next State.Wait_rom;
                rom_addr <-- rom_addr_val +:. 1;
            ] [
              state.set_next State.Wait_rom;
              rom_addr <-- rom_addr_val +:. 1;
            ];
          ]
        ];
      ];

      State.Parse_upper, [
        if_ is_digit [
          parsed_upper_bin <-- (uresize (parsed_upper_bin_val *: (of_int ~width:128 10)) 128) +: uresize digit_val 128;
          parsed_upper_bcd <-- (sll parsed_upper_bcd_val 4) +: uresize digit_val 80;
          upper_digits <-- upper_digits_val +:. 1;
          rom_addr <-- rom_addr_val +:. 1;
          next_state_after_wait <-- of_int ~width:state_width (State.to_int State.Parse_upper);
          state.set_next State.Wait_rom;
        ] [
          state.set_next State.Setup_calc;
          current_range_start <-- uresize (parsed_lower_bin_val) 64;
          current_range_end <-- uresize (parsed_upper_bin_val) 64;
          current_d <-- lower_digits_val;

          if_ is_comma [
            rom_addr <-- rom_addr_val +:. 1;
            next_state_after_wait <-- of_int ~width:state_width (State.to_int State.Parse_lower);
          ] [
            next_state_after_wait <-- of_int ~width:state_width (State.to_int State.Done);
          ]
        ];
      ];

      State.Setup_calc, [
        if_ (current_range_start_val >: current_range_end_val) [
            parsed_lower_bin <--. 0;
            parsed_upper_bin <--. 0;
            parsed_lower_bcd <--. 0;
            parsed_upper_bcd <--. 0;
            lower_digits <--. 0;
            upper_digits <--. 0;

            let next_state_val_ = next_state_val in
            let finished_val = of_int ~width:state_width (State.to_int State.Done) in

            if_ (next_state_val_ ==: finished_val) [
              state.set_next State.Done;
            ] [
              state.set_next State.Wait_rom;
            ];
        ] [
          calc_d <-- uresize (current_d_val) 5;
          calc_range_start <-- current_range_start_val;

          if_ (upper_digits_val >: current_d_val) [
            calc_range_end <-- ones 64;
          ] [
            calc_range_end <-- current_range_end_val;
          ];

          if_ (current_d_val >: lower_digits_val) [
              calc_lower_bcd <--. 0;
          ] [
            calc_lower_bcd <-- parsed_lower_bcd_val;
          ];

          calc_upper_bcd <-- parsed_upper_bcd_val;
          calc_start <--. 1;
          state.set_next State.Wait_summers;
        ];
      ];

      State.Calc_loop, [
        current_d <-- current_d_val +:. 1;
        state.set_next State.Setup_calc;

        if_ (current_d_val <: (of_int ~width:6 19)) [
          current_range_start <-- pow10 (current_d_val);
        ] [
          current_range_start <-- ones 64;
        ];
      ];

      State.Wait_summers, [
        calc_start <--. 0;
        if_ finished_summer [
          part1 <-- part1_val +: chunk_sum_part1;
          part2 <-- part2_val +: chunk_sum_part2;
          state.set_next State.Calc_loop;
        ] [];
      ];

      State.Done, [
        finished_out <--. 1;
      ];
    ];
  ]);

  {
    O.
    rom_addr = rom_addr_val;
    part1_result = part1_val;
    part2_result = part2_val;
    finished = Always.Variable.value finished_out;
  }
