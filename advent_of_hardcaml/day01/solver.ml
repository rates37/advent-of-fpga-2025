open Hardcaml
open Signal

module I = struct
  type 'a t = {
    clock: 'a;
    clear: 'a;

    (* Signals from decoder *)
    input_valid: 'a; 
    dir: 'a;
    rotation: 'a [@bits 16];
  }
  [@@deriving hardcaml]
end


module O = struct
  type 'a t = {
    part1_result: 'a [@bits 16];
    part2_result: 'a [@bits 16];
  }
  [@@deriving hardcaml]
end

(* Todo: find a better approach to this T.T *)
(* Module to perform division 
Will synthesise to a horrifically deep circuit
 *)

let div_mod_100 ~(dividend : Signal.t) : Signal.t * Signal.t = 
  let hundred = of_int ~width:16 100 in
  let dividend_16 = uresize dividend 16 in

  let rec compute_quotient q r i = 
    if i = 0 then (q,r) 
    else 
      let can_sub = r >=: hundred in
      let r_next = mux2 can_sub (r -: hundred) r in
      let q_next = mux2 can_sub (q +:. 1) q in
      compute_quotient r_next q_next (i-1)
  in compute_quotient (zero 16) dividend_16 656


  let create _scope (i: Signal.t I.t) = 
    let open I in 
    let spec = Reg_spec.create ~clock:i.clock () in

    (* Instantiate div-modder *)
    let full_rotations, steps_mod_100 = div_mod_100 ~dividend:i.rotation in

    (* State: *)
    let dial_pos_wire = wire 7 in
    let dial_pos_reg = reg spec dial_pos_wire in
    let part1_wire = wire 16 in
    let part1_reg = reg spec part1_wire in
    let part2_wire = wire 16 in
    let part2_reg = reg spec part2_wire in

    (* current dial position *)
    let pos_9 = uresize dial_pos_reg 9 in
    let steps_9 = uresize (sel_bottom steps_mod_100 8) 9 in 
    let dial_pos_not_zero = dial_pos_reg <>:. 0 in 
    let pos_unwrapped_right = pos_9 +: steps_9 in
    let pos_10_signed = uresize dial_pos_reg 10 in
    let steps_10_signed = uresize (sel_bottom steps_mod_100 8) 10 in
    let pos_unwrapped_left = pos_10_signed -: steps_10_signed in

    (* check if crossed zero *)
    let hundred_9 = of_int ~width:9 100 in
    let zero_10 = of_int ~width:10 0 in 
    let right_crosses = dial_pos_not_zero &: (pos_unwrapped_right >=: hundred_9) in
    let left_crosses = dial_pos_not_zero &: (pos_unwrapped_left <=+ zero_10) in

    (* new dial position: *)
    let dial_pos_8 = uresize dial_pos_reg 8 in
    let steps_8 = sel_bottom steps_mod_100 8 in
    let hundred_8 = of_int ~width:8 100 in
    let pos_plus_steps = dial_pos_8 +: steps_8 in
    let new_pos_right = mux2 (pos_plus_steps >=: hundred_8) (sel_bottom (pos_plus_steps -: hundred_8) 7) (sel_bottom pos_plus_steps 7) in
    let pos_plus_100_minus_steps = dial_pos_8 +: hundred_8 -: steps_8 in 
    let new_pos_left = mux2 (pos_plus_100_minus_steps >=: hundred_8) (sel_bottom (pos_plus_100_minus_steps -: hundred_8) 7) (sel_bottom pos_plus_100_minus_steps 7) in

    let new_dial_pos = mux2 (i.dir) new_pos_right new_pos_left in
    let passed_landed = mux2 (i.dir) right_crosses left_crosses in

    let total_crossings_this_rotation = 
      full_rotations +: uresize passed_landed 16
    in 

    let lands_on_zero = (new_dial_pos ==:. 0) in
    let next_dial_pos = mux2 (i.clear) (of_int ~width:7 50) (mux2 (i.input_valid) (new_dial_pos) (dial_pos_reg)) in
    let part1_next = mux2 (i.clear) (zero 16) (mux2 (i.input_valid &: lands_on_zero) (part1_reg +:.1 ) (part1_reg)) in
    let part2_next = mux2 (i.clear) (zero 16) (mux2 (i.input_valid) (part2_reg +: total_crossings_this_rotation) (part2_reg)) in
    dial_pos_wire <== next_dial_pos;
    part1_wire <== part1_next;
    part2_wire <== part2_next;

    { O. 
      part1_result = part1_reg;
      part2_result = part2_reg;
    }

let hierarchy scope (input: Signal.t I.t) =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~scope ~name:"solver" create input
