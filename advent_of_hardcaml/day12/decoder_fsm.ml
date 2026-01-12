open! Hardcaml
open! Signal

module Make (Cfg: Config.S) = struct
  module I = struct
    type 'a t = {
      clock: 'a;
      clear: 'a;
      rom_data: 'a [@bits 8];
      rom_valid: 'a;
    }
    [@@deriving hardcaml]
  end

    type 'a output = {
      rom_addr: 'a;
      shape_hash_counts: 'a array;
      region_width: 'a;
      region_height: 'a;
      region_counts: 'a array;
      region_valid: 'a;
      done_: 'a;
    }

  (* FSM: *)
  module State = struct
    type t = 
      | Startup
      | Wait_for_shape_id
      | Skip_to_grid
      | Parse_grid
      | Skip_empty_line
      | Parse_width
      | Parse_height
      | Skip_colon
      | Parse_count
      | Done
    [@@deriving sexp_of, compare, enumerate]
  end

  let create _scope (i: Signal.t I.t) = 
    let open I in 
    let spec = Reg_spec.create ~clock: i.clock ~clear:i.clear () in

    (* Constants: *)
    let ascii_hash = of_int ~width:8 (Char.code '#') in
    let ascii_colon = of_int ~width:8 (Char.code ':') in
    let ascii_x = of_int ~width:8 (Char.code 'x') in
    let ascii_space = of_int ~width:8 (Char.code ' ') in
    let ascii_0 = of_int ~width:8 (Char.code '0') in
    let ascii_9 = of_int ~width:8 (Char.code '9') in
    let ascii_newline = of_int ~width:8 (Char.code '\n') in

    (* variables *)
    let state = Always.State_machine.create (module State) spec in
    let rom_addr = Always.Variable.reg spec ~enable:vdd ~width:Cfg.rom_addr_width in
    let current_shape_idx = Always.Variable.reg spec ~enable:vdd ~width:8 in
    let current_hash_count = Always.Variable.reg spec ~enable:vdd ~width:8 in
    let prev_was_newline = Always.Variable.reg spec ~enable:vdd ~width:1 in

    let shape_hash_regs = 
      let arr = Array.make Cfg.num_shapes (Always.Variable.reg spec ~enable:vdd ~width:8) in 
      for idx = 0 to Cfg.num_shapes - 1 do
        arr.(idx) <- Always.Variable.reg spec ~enable:vdd ~width:8
      done;
      arr
    in

    let region_width = Always.Variable.reg spec ~enable:vdd ~width:8 in
    let region_height = Always.Variable.reg spec ~enable:vdd ~width:8 in

    let region_count_regs = 
      let arr = Array.make Cfg.num_shapes (Always.Variable.reg spec ~enable:vdd ~width:8) in
      for idx = 0 to Cfg.num_shapes - 1 do
        arr.(idx) <- Always.Variable.reg spec ~enable:vdd ~width:8
      done;
      arr
    in

    let current_count_idx = Always.Variable.reg spec ~enable:vdd ~width:8 in
    let current_number = Always.Variable.reg spec ~enable:vdd ~width:8 in
    let region_valid_reg = Always.Variable.reg spec ~enable:vdd ~width:1 in
    let is_digit = (i.rom_data >=: ascii_0) &: (i.rom_data <=: ascii_9) in
    let digit_val = uresize (i.rom_data -: ascii_0) 8 in

    let rom_addr_v = Always.Variable.value rom_addr in
    let current_shape_idx_v = Always.Variable.value current_shape_idx in
    let current_hash_count_v = Always.Variable.value current_hash_count in
    let current_count_idx_v = Always.Variable.value current_count_idx in
    let current_number_v = Always.Variable.value current_number in
    let prev_was_newline_v = Always.Variable.value prev_was_newline in
    let last_shape_idx = Cfg.num_shapes - 1 in
    let store_shape_hash_count = 
      let rec build_list idx acc = 
        if idx < 0 then acc
        else build_list (idx - 1)
          (Always.(when_ (current_shape_idx_v ==:. idx) [
            shape_hash_regs.(idx) <-- current_hash_count_v;
          ]) :: acc)
      in
      build_list (Cfg.num_shapes - 1) [] 
    in

    let store_region_count =
      let rec build_list idx acc = 
        if idx < 0 then acc 
        else build_list (idx - 1) (
          Always.(when_ (current_count_idx_v ==:. idx) [
            region_count_regs.(idx) <-- current_number_v;
          ]) :: acc)
      in build_list (Cfg.num_shapes - 1) []
    in

    Always.(compile [
      region_valid_reg <--. 0;

      state.switch [
        State.Startup, [
          rom_addr <--. 0;
          state.set_next State.Wait_for_shape_id;
        ];

        State.Wait_for_shape_id, [
          when_ i.rom_valid [
            rom_addr <-- rom_addr_v +:. 1;
            when_ is_digit [
              current_shape_idx <-- uresize digit_val 8;
              current_hash_count <--. 0;
              prev_was_newline <--. 0;
              state.set_next State.Skip_to_grid;
            ];
          ];
          when_ (~:(i.rom_valid)) [ 
            state.set_next State.Done;
          ];
        ];

        State.Skip_to_grid, [
          when_ i.rom_valid [
            rom_addr <-- rom_addr_v +:. 1;
            when_ (i.rom_data ==: ascii_newline) [
              state.set_next State.Parse_grid;
            ];

            when_ (~:(i.rom_valid)) [
              state.set_next State.Done;
            ];
          ];
        ];

        State.Parse_grid, [
          when_ i.rom_valid [
            rom_addr <-- rom_addr_v +:. 1;
            when_ (i.rom_data ==: ascii_hash) [
              current_hash_count <-- current_hash_count_v +:. 1;
              prev_was_newline <--. 0;
            ];

            when_ (i.rom_data ==: ascii_newline) [
              if_ prev_was_newline_v [
                proc store_shape_hash_count;
                if_ (current_shape_idx_v ==:. last_shape_idx) [
                  state.set_next State.Skip_empty_line;
                ] [
                  state.set_next State.Wait_for_shape_id;
                ];
              ] [
                prev_was_newline <--. 1;
              ];
            ];

            when_ ((i.rom_data <>: ascii_newline) &: (i.rom_data <>: ascii_hash)) [
              prev_was_newline <--. 0;
            ];
          ];

          when_ (~:(i.rom_valid)) [
            state.set_next State.Done;
          ];
        ];

        State.Skip_empty_line, [
          when_ i.rom_valid [
            rom_addr <-- rom_addr_v +:. 1;
            when_ is_digit [
              region_width <-- digit_val;
              state.set_next State.Parse_width;
            ]
          ];
          when_ (~:(i.rom_valid)) [
            state.set_next State.Done;
          ];
        ];

        State.Parse_width, [
          when_ i.rom_valid [
            rom_addr <-- rom_addr_v +:. 1;
            when_ is_digit [
              region_width <-- (sll (Always.Variable.value region_width) 3 +:
                                sll (Always.Variable.value region_width) 1 +: 
                                digit_val
                                );
            ];

            when_ (i.rom_data ==: ascii_x) [
              region_height <--. 0;
              state.set_next State.Parse_height;
            ];
          ];

          when_ (~:(i.rom_valid)) [
            state.set_next State.Done;
          ]
        ];

        State.Parse_height, [
          when_ i.rom_valid [
            rom_addr <-- rom_addr_v +:. 1;
            when_ is_digit [
              region_height <-- (sll (Always.Variable.value region_height) 3 +:
                                 sll (Always.Variable.value region_height) 1 +:
                                 digit_val);
            ];

            when_ (i.rom_data ==: ascii_colon) [
              current_count_idx <--. 0;
              current_number <--. 0;
              state.set_next State.Skip_colon;
            ];
          ];

          when_ (~:(i.rom_valid)) [
            state.set_next State.Done;
          ]
        ];

        State.Skip_colon, [
          when_ i.rom_valid [
            rom_addr <-- rom_addr_v +:. 1;
            when_ (i.rom_data ==: ascii_space) [
              state.set_next State.Parse_count;
            ];
          ];
          when_ (~:(i.rom_valid)) [
            state.set_next State.Done;
          ];
        ];

        State.Parse_count, [
          when_ i.rom_valid [
            rom_addr <-- rom_addr_v +:. 1;
            when_ is_digit [
              current_number <-- (sll current_number_v 3 +: sll current_number_v 1 +: digit_val);
            ];

            when_ (i.rom_data ==: ascii_space) [
              proc store_region_count;
              current_count_idx <-- current_count_idx_v +:. 1;
              current_number <--. 0;
            ];

            when_ (i.rom_data ==: ascii_newline) [
              region_count_regs.(last_shape_idx) <-- current_number_v;
              region_valid_reg <--. 1;
              state.set_next State.Skip_empty_line;
            ];
          ];

          when_ (~:(i.rom_valid)) [
            state.set_next State.Done;
          ];
        ];

        State.Done, [ ];
      ];
    ]);

    let shape_hash_counts = Array.map Always.Variable.value shape_hash_regs in
    let region_counts = Array.mapi (fun idx reg -> 
      let reg_val = Always.Variable.value reg in
      if idx = last_shape_idx then 
        mux2 (Always.Variable.value region_valid_reg) current_number_v reg_val
      else
        reg_val
    ) region_count_regs in

    { rom_addr = rom_addr_v;
      shape_hash_counts;
      region_width = Always.Variable.value region_width;
      region_height = Always.Variable.value region_height;
      region_counts;
      region_valid = Always.Variable.value region_valid_reg;
      done_ = state.is State.Done;
    }
end

module Default = Make(Config.Default)
