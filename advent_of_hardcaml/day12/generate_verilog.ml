open! Hardcaml
open! Hardcaml.Rtl

module Core = Day12.Day12_core.Default
(* Run: `dune exec day12/generate_verilog.exe -- path/to/output/file.v` *)
let () = 
  let output_file = 
    if Array.length Sys.argv > 1 then Sys.argv.(1) else "day12_core.v"
  in

  let scope = Scope.create ~flatten_design:false () in 
  let module Circ = Circuit.With_interface (Core.I) (Core.O) in
  let circuit = Circ.create_exn ~name:"day12_core" (Core.create scope) in 
  Out_channel.with_open_text output_file (fun oc -> output ~output_mode:(To_channel oc) Verilog circuit);
  Printf.printf "Generated verilog in: %s\n" output_file;
