open! Hardcaml


let () = 
let filename = if Array.length Sys.argv > 1 then Sys.argv.(1) else "input.txt" in

Printf.printf "Loading input from file: %s\n" filename;

(* Load file with rom util: *)
let rom = Utils.Rom.load_file filename in
Printf.printf "Loaded %d characters into rom\n" rom.size;

(* Instantiate DUT *)
let scope = Scope.create ~flatten_design:true () in 
let module Circuit = Circuit.With_interface (Day02.Day02_core.I) (Day02.Day02_core.O) in 
let circuit = Circuit.create_exn ~name:"u_day02_0" (Day02.Day02_core.create scope) in

(* Simulation controls: *)
let sim = Cyclesim.create circuit in
let inputs = Cyclesim.inputs sim in 
let outputs = Cyclesim.outputs sim in 
let i_clear = List.assoc "clear" inputs in
let i_rom_data = List.assoc "rom_data" inputs in
let i_rom_valid = List.assoc "rom_valid" inputs in
let o_rom_addr = List.assoc "rom_addr" outputs in
let o_part_1 = List.assoc "part1_result" outputs in
let o_part_2 = List.assoc "part2_result" outputs in
let o_done = List.assoc "finished" outputs in

(* Count clock cycles: *)
let cycle_count = ref 0 in

(* Reset all modules: *)
i_clear := Bits.vdd;
for _ = 1 to 5 do
  Cyclesim.cycle sim;
done;
i_clear := Bits.gnd;

let addr = Bits.to_int !o_rom_addr in 
let data,valid = Utils.Rom.read rom addr in 
i_rom_data := Bits.of_int ~width:8 data;
i_rom_valid := if valid then Bits.vdd else Bits.gnd;

while Bits.to_int !o_done = 0 do
  Cyclesim.cycle sim;
  incr cycle_count;

  (* Update rom: *)
  let addr = Bits.to_int !o_rom_addr in 
  let data,valid = Utils.Rom.read rom addr in 
  i_rom_data := Bits.of_int ~width:8 data;
  i_rom_valid := if valid then Bits.vdd else Bits.gnd;

  (* Check max number of cycles to prevent infinite loop *)
  if !cycle_count > 1000000 then begin
    Printf.printf "Simulation exceeded 1000000 cycles, aborting.\n";
    exit 1
  end
done;

(* Print results: *)
let part1_res = Bits.to_int !o_part_1 in
let part2_res = Bits.to_int !o_part_2 in
Printf.printf "Day 02 complete\n";
Printf.printf "Part 1 result: %d\n" part1_res;
Printf.printf "Part 2 result: %d\n" part2_res;
Printf.printf "Took %d clock cycles\n" !cycle_count;
