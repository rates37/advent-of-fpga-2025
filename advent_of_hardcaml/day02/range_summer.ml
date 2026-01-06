(* Sum invalid numbers in the range [A,B] with D digits *)

open! Hardcaml
open! Signal

module I = struct
  type 'a t = {
    clock: 'a;
    clear: 'a;
    start: 'a;
    d: 'a [@bits 5];
    range_start : 'a [@bits 64];
    range_end : 'a [@bits 64];
    parsed_lower_bcd: 'a [@bits 80];
    parsed_upper_bcd: 'a [@bits 80];
  }
  [@@deriving hardcaml]
end


module O = struct
  type 'a t = {
    sum_out: 'a [@bits 64];
    part_1_sum_out: 'a [@bits 64];
    finished : 'a;
  }
  [@@deriving hardcaml]
end

module State = struct 
  type t = 
    | Idle
    | Process_periods
    | Wait_summer_start
    | Wait_result
  [@@deriving sexp_of, compare, enumerate]
end


(* Lookup table for multipliers/operators *)
let lookup_params (d: Signal.t) = 
  (* Default all zeros *)
  let def_p1 = mux2 (d >:. 1) (one 5) (zero 5) in
  let def_p2 = zero 5 in 
  let def_p3 = zero 5 in
  let def_op1 = mux2 (d >:. 1) (zero 2) (of_int ~width:2 2) in
  let def_op2 = of_int ~width:2 2 in
  let def_op3 = of_int ~width:2 2 in

  let pack p1 p2 p3 op1 op2 op3 = 
    [
      of_int ~width: 5 p1;
      of_int ~width:5 p2;
      of_int ~width:5 p3;
      of_int ~width:2 op1;
      of_int ~width:2 op2;
      of_int ~width:2 op3;
    ] in
  let case_list = [
    4, pack 2 1 0 0 2 2;
    6, pack 3 2 1 0 0 1;
    8, pack 4 0 0 0 2 2;
    9, pack 3 0 0 0 2 2;
    10, pack 5 2 1 0 0 1;
    12, pack 6 4 2 0 0 1;
    14, pack 7 2 1 0 0 1;
    15, pack 5 3 1 0 0 1;
    16, pack 8 0 0 0 2 2;
    18, pack 9 6 3 0 0 1;
    20, pack 10 4 2 0 0 1;
  ] in 

  let match_d v = d ==:. v in
  let default_vals = [def_p1; def_p2; def_p3; def_op1; def_op2; def_op3] in
  let results = 
    List.fold_left (fun current (val_m, vals_m) -> 
      let m = match_d val_m in 
      List.map2 (fun v_m v_curr -> mux2 m v_m v_curr) vals_m current) default_vals case_list
    in
  
    match results with
      | [a; b; c; d; e; f] -> a, b, c, d, e, f
      | _ -> failwith "Something has gone terribly wrong"

let create scope (i: Signal.t I.t) = 
  let open I in
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
  let state = Always.State_machine.create (module State) spec in

  let p1, p2, p3, op1, op2, op3 = lookup_params i.d in

  let period_l = Always.Variable.reg spec ~enable:vdd ~width:5 in
  let period_idx = Always.Variable.reg spec ~enable:vdd ~width:2 in
  let period_go = Always.Variable.reg spec ~enable:vdd ~width:1 in
  let finished_reg = Always.Variable.reg spec ~enable:vdd ~width:1 in
  let sum_out_reg = Always.Variable.reg spec ~enable:vdd ~width:64 in
  let part1_sum_out_reg = Always.Variable.reg spec ~enable:vdd ~width:64 in

  let p1_reg = Always.Variable.reg spec ~enable:vdd ~width:5 in
  let p2_reg = Always.Variable.reg spec ~enable:vdd ~width:5 in
  let p3_reg = Always.Variable.reg spec ~enable:vdd ~width:5 in
  let op1_reg = Always.Variable.reg spec ~enable:vdd ~width:2 in
  let op2_reg = Always.Variable.reg spec ~enable:vdd ~width:2 in
  let op3_reg = Always.Variable.reg spec ~enable:vdd ~width:2 in

  let period_idx_val = Always.Variable.value period_idx in
  let p1_val = Always.Variable.value p1_reg in 
  let p2_val = Always.Variable.value p2_reg in 
  let p3_val = Always.Variable.value p3_reg in 
  let op1_val = Always.Variable.value op1_reg in
  let op2_val = Always.Variable.value op2_reg in
  let op3_val = Always.Variable.value op3_reg in
  let next_l = Always.Variable.wire ~default:(zero 5) in 
  let next_op = Always.Variable.wire ~default:(zero 2) in
  let sum_out_val = Always.Variable.value sum_out_reg in

  (* Instantiate period summer *)
  let period_summer_start = Always.Variable.value period_go in
  let period_summer_i = {
    Period_summer.I.clock = i.clock;
    clear = i.clear;
    start = period_summer_start;
    limit_lower = i.range_start;
    limit_upper = i.range_end;
    parsed_lower_bcd = i.parsed_lower_bcd;
    parsed_upper_bcd = i.parsed_upper_bcd;
    d = i.d;
    l = Always.Variable.value period_l;
  } in 
  let period_summer_o = Period_summer.create scope period_summer_i in
  let { Period_summer.O. finished = period_done; sum = period_sum } = period_summer_o in

  (* FSM Logic: *)
  Always.(compile [
    state.switch [
      State.Idle, [
        finished_reg <--. 0;
        when_ i.start [
          part1_sum_out_reg <--. 0;
          sum_out_reg <--. 0;
          (* Latch multipliers/parameters *)
          p1_reg <-- p1;
          p2_reg <-- p2;
          p3_reg <-- p3;
          op1_reg <-- op1;
          op2_reg <-- op2;
          op3_reg <-- op3;

          period_idx <--. 0;
          state.set_next State.Process_periods;
        ];
      ];

      State.Process_periods, [
        (* Select next L and operation based on period index: *)
        if_ (period_idx_val ==:. 0) [
          next_l <-- p1_val;
          next_op <-- op1_val;
        ] [
          if_ (period_idx_val ==:. 1) [
              next_l <-- p2_val;
              next_op <-- op2_val;
          ] [
            if_ (period_idx_val ==:. 2) [
                next_l <-- p3_val;
                next_op <-- op3_val;
            ] [
              next_l <--. 0;
              next_op <--. 2;
            ];
          ];
        ];

        if_ ((Always.Variable.value next_op ==:. 2) |: (Always.Variable.value next_l ==:. 0)) [
          finished_reg <--. 1;
          state.set_next State.Idle;
        ] [
          period_l <-- Always.Variable.value next_l;
          period_go <--. 1;
          state.set_next State.Wait_summer_start;
        ];

      ];

      State.Wait_summer_start, [
        period_go <--. 0;
        if_ (~: period_done) [
            state.set_next State.Wait_result;
        ] [];
      ];

      State.Wait_result, [
        when_ period_done (
          (* Identify current op *)
          let cur_op = mux period_idx_val [op1_val; op2_val; op3_val] in
          [
            (* Part 1 logic *)
            when_ ((period_idx_val ==:. 0) &: ((i.d).:[0,0] ==:. 0)) [
              part1_sum_out_reg <-- period_sum;
            ];

            (* Accumulate part 2: *)
            if_ (cur_op ==:. 0) [
              sum_out_reg <-- sum_out_val +: period_sum;
            ] [
              sum_out_reg <-- sum_out_val -: period_sum;
            ];

            period_idx <-- period_idx_val +:. 1;
            state.set_next State.Process_periods;
          ]
        );
      ];
    ];
  ]);
    { O.
    sum_out = Always.Variable.value sum_out_reg;
    part_1_sum_out = Always.Variable.value part1_sum_out_reg;
    finished = Always.Variable.value finished_reg;

    }
