open Hardcaml
open Signal

module I = struct
  type 'a t = {
    clock: 'a;
    clear: 'a;
    rom_data: 'a [@bits 8];
    rom_valid: 'a [@bits 1];
  }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t = {
    rom_addr: 'a [@bits 17];
    part1_result: 'a [@bits 16];
    part2_result: 'a [@bits 16];
    finished: 'a;
  }
  [@@deriving hardcaml]
end


(* Define core FSM states: *)
module State = struct 
  type t = 
    | Start
    | Running
    | Done
  [@@deriving sexp_of, compare, enumerate]
end

let create scope (i: Signal.t I.t) = 
  let open I in
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear() in

  (* Variables/Registers *)
  let state = Always.State_machine.create (module State) spec in
  let rom_addr = Always.Variable.reg spec ~enable:vdd ~width:17 in
  let done_flag = Always.Variable.reg spec ~enable:vdd ~width:1 in
  let decoder_enable = (state.is State.Running) &: i.rom_valid in

  (* Instantiate FSM *)
  let decoder_out = Decoder_fsm.hierarchy scope
  {
    Decoder_fsm.I.
    clock = i.clock;
    clear = i.clear;
    char_in = i.rom_data;
    char_valid = decoder_enable;
  } in

  (* Instantiate solver: *)
  let solver_out = Solver.hierarchy scope
  {
    Solver.I.
    clock = i.clock;
    clear = i.clear;
    input_valid = decoder_out.valid_pulse;
    dir = decoder_out.dir;
    rotation = decoder_out.number;
  } in

  (* FSM logic: *)
  Always.(compile [
    state.switch [
      State.Start, [
        rom_addr <--. 0;
        state.set_next State.Running;
      ];

      State.Running, [
        if_ i.rom_valid [
          rom_addr <-- Always.Variable.value rom_addr +:. 1;
        ] [
          (* Assume invalid rom == end of file *)
          state.set_next State.Done;
        ];
      ];

      State.Done, [
        done_flag <--. 1;
      ];
    ]
  ]);
  {
    O.
    rom_addr = Always.Variable.value rom_addr;
    part1_result = solver_out.part1_result;
    part2_result = solver_out.part2_result;
    finished = Always.Variable.value done_flag;
  }

let hierarchy scope (input: Signal.t I.t) = 
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~scope ~name:"day01_core" create input
