open! Hardcaml
open! Signal

module I  = struct
  type 'a t = {
    clock: 'a;
    clear: 'a;
    start: 'a;
    limit_lower: 'a [@bits 64];
    limit_upper: 'a [@bits 64];
    parsed_lower_bcd: 'a [@bits 80];
    parsed_upper_bcd: 'a [@bits 80];
    d: 'a [@bits 5]; (* Total number of digits*)
    l: 'a [@bits 5]; (* Length of repeating pattern to check *)
  }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t = {
    finished: 'a;
    sum: 'a [@bits 64];
  }
  [@@deriving hardcaml]
end


module State = struct
  type t = 
    | Idle
    | Calc_m
    | Calc_min
    | Calc_max
    | Setup_sum
    | Calc_sum
    [@@deriving sexp_of, compare, enumerate]
end



let extract_seed (bcd: Signal.t) (d: Signal.t) (l: Signal.t) = 
  (* Get nibbles (4-bit chunks) for each digit in input: *)
  let nibbles = List.init 20 (fun i -> bcd.:[(i*4) + 3, i*4]) in
  let zero64 = zero 64 in
  let ten = of_int ~width:64 10 in

  let rec build_seed acc i =
    if i >= 20 then acc 
    else
      let idx_signal = d -: (of_int ~width:5 (1+i)) in
      let nibble_at_idx = uresize (mux idx_signal nibbles) 64 in
      let should_process = of_int ~width:5 i <: l in
      let new_acc = mux2 should_process (uresize (acc *: ten) 64 +: nibble_at_idx) acc in
      build_seed new_acc (i+1)
    in
  build_seed zero64 0

let powers_of_10 = List.init 20 (fun i -> let v = Z.pow (Z.of_int 10) i in of_string (Z.format "%b" v) |> fun s -> uresize s 64)

let pow10 p = mux p powers_of_10

let create _scope (i: Signal.t I.t) = 
  let open I in
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
  let state = Always.State_machine.create (module State) spec in

  let m_reg = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let s_min_reg = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let s_max_reg = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let sum_reg = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let finished_reg = Always.Variable.reg spec ~enable:vdd ~width:1 in
  let count = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let sum_ab = Always.Variable.reg spec ~enable:vdd ~width:64 in

  let m_val = Always.Variable.value m_reg in
  let s_min_val = Always.Variable.value s_min_reg in
  let s_max_val = Always.Variable.value s_max_reg in
  let sum_ab_val = Always.Variable.value sum_ab in
  let count_val = Always.Variable.value count in

  let limit_upper_bignum = i.limit_upper >: (of_string "64'hF000000000000000") in

  let final_m = 
    List.fold_left (fun acc k -> 
      let k_val = of_int ~width:6 ((k+1)) in
      let l_ext = uresize i.l 6 in
      let d_ext = uresize i.d 6 in
      let prod = k_val *: l_ext in
      let k_l_val = of_int ~width:6 k *: l_ext in
      let added_val = uresize(acc +: pow10 (uresize k_l_val 5)) 64 in
      mux2 (prod <=: uresize d_ext 12) added_val acc
      ) (zero 64) (List.init 20 Fun.id) in

  Always.(compile [
      state.switch [
        State.Idle, [
          finished_reg <--. 0;
          when_ i.start [
            m_reg <--. 0;
            state.set_next State.Calc_m;
          ];
        ];

        State.Calc_m, [
          m_reg <-- final_m;
          state.set_next State.Calc_min;
        ];

        State.Calc_min, [
          if_ (i.limit_lower ==:. 0) [
            s_min_reg <-- pow10 (i.l -:. 1);
          ] [
            let seed_raw = extract_seed i.parsed_lower_bcd i.d i.l in
            let min_val = pow10 (i.l -:. 1) in 
            let seed_val = mux2 (seed_raw <: min_val) min_val seed_raw in

            (* clip min *)
            if_ ((seed_val *: m_val) <: uresize i.limit_lower 128) [
              s_min_reg <-- seed_val +:. 1;
            ] [
              s_min_reg <-- seed_val;
            ];
          ];
          state.set_next State.Calc_max;
        ];

        State.Calc_max, [
          if_ limit_upper_bignum [
            s_max_reg <-- pow10 i.l -:. 1;
          ] [
            let seed_val = extract_seed i.parsed_upper_bcd i.d i.l in

            (* clip max *)
            if_ ((seed_val *: m_val) >: uresize i.limit_upper 128) [
              s_max_reg <-- seed_val -:. 1;
            ] [
              s_max_reg <-- seed_val;
            ];
          ];
          state.set_next State.Setup_sum;
        ];

        State.Setup_sum, [
          if_ (s_max_val <: s_min_val) [
            sum_reg <--. 0;
            finished_reg <--. 1;
            state.set_next State.Idle;
          ] [
            count <-- s_max_val -: s_min_val +:. 1;
            sum_ab <-- s_max_val +: s_min_val;
            state.set_next State.Calc_sum;
          ];
        ];

        State.Calc_sum, [
          if_ ((count_val).:[0,0] ==:. 0) [
            sum_reg <-- uresize (m_val *: sum_ab_val *: (srl count_val 1)) 64;
          ] [
            sum_reg <-- uresize (m_val *: (srl sum_ab_val 1) *: count_val) 64;
          ];
          finished_reg <--. 1;
          state.set_next State.Idle;
        ];
      ];
  ]);
  {
    O.
    finished = Always.Variable.value finished_reg;
    sum = Always.Variable.value sum_reg;
  }
