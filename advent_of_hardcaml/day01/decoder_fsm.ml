open Hardcaml
open Signal

module I = struct
  type 'a t = {
    clock: 'a;
    clear: 'a; (* clear in stead of rst / rst_n*)
    char_in: 'a [@bits 8]; (* from rom*)
    char_valid: 'a; (* from rom*)
  }
  [@@deriving hardcaml]
end


module O = struct
  type 'a t = {
    dir: 'a;
    number: 'a [@bits 16];
    valid_pulse: 'a;
  }
  [@@deriving hardcaml]
end

(* Define FSM states: *)
module State = struct
  type t = 
    | Idle
    | Reading
    [@@deriving sexp_of, compare, enumerate]
end


let create _scope (i: Signal.t I.t) = 
  let open I in 
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in

  (* Define symbols to use *)
  let ascii_L = of_int ~width:8 (Char.code 'L') in
  let ascii_R = of_int ~width:8 (Char.code 'R') in
  let ascii_0 = of_int ~width:8 (Char.code '0') in
  let ascii_9 = of_int ~width:8 (Char.code '9') in
  let ascii_n = of_int ~width:8 (Char.code '\n') in

  let state = Always.State_machine.create (module State) spec in
  let number_acc = Always.Variable.reg spec ~enable:vdd ~width:16 in
  let dir_internal = Always.Variable.reg spec ~enable:vdd ~width:1 in

  (* Outputs: *)
  let dir_out =  Always.Variable.reg spec ~enable:vdd ~width:1 in
  let number_out = Always.Variable.reg spec ~enable:vdd ~width:16 in
  let valid_pulse =  Always.Variable.reg spec ~enable:vdd ~width:1 in

  (* Helper signals *)
  let is_digit = (i.char_in >=: ascii_0) &: (i.char_in <=: ascii_9) in
  (* Todo: should be able to just take bottom 4 bits rather than subtraction? *)
  let digit_value = uresize (i.char_in -: ascii_0) 16 in

  (* FSM logic: *)
  Always.(compile [
    (* Default, set valid to 0: *)
    valid_pulse <--. 0;

    state.switch [
      State.Idle, [
        when_ i.char_valid [
          number_acc <--. 0;
          when_ (i.char_in ==:ascii_L) [
            dir_internal <--. 0;
            state.set_next State.Reading;
          ];

          when_ (i.char_in ==:ascii_R) [
            dir_internal <--. 1;
            state.set_next State.Reading;
          ];
        ];
      ];

      State.Reading, [
        when_ i.char_valid [
          when_ is_digit [
            (* acc = acc * 10 + digit_value *)
            number_acc <-- (sll (Always.Variable.value number_acc) 3 +:
            sll (Always.Variable.value number_acc) 1 +:
            digit_value);
          ];

          when_ (i.char_in ==: ascii_n) [
            dir_out <-- Always.Variable.value dir_internal;
            number_out <-- Always.Variable.value number_acc;
            valid_pulse <--. 1;
            state.set_next State.Idle;
          ];

          (* Go to idle to recover if invalid char encountered: *)
          when_ (~:is_digit &: (i.char_in <>: ascii_n)) [
            state.set_next State.Idle;
          ];
        ];
      ];
    ];
  ]);
  { O.
    dir = Always.Variable.value dir_out;
    number = Always.Variable.value number_out;
    valid_pulse = Always.Variable.value valid_pulse;
  }


let hierarchy scope (input: Signal.t I.t) =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~scope ~name:"decoder_fsm" create input
