(*
module to load a file into byte-addressable ROM
is NOT a synthesisable module
this is used to show proof of concept for the 
validity of the solver (not as part of the solution)

Translated (roughly-ish) from verilog/utils/rom.v
*)
open! Stdio

(* Type to represent loaded ROM file contents *)
type t = {
  data : int array; (* byte array *)
  size: int;
}

(* Load a file into rom type, takes in filename, 
  returns a byte addressable rom with newline + \0 
  terminator *)
let load_file (filename: string) : t = 
  let ic = In_channel.create filename in 
  let contents = In_channel.input_all ic in
  In_channel.close ic;

  let len = String.length contents in
  let data = Array.make (len + 3) 0 in
  for i = 0 to len - 1 do
    data.(i) <- Char.code contents.[i]
  done;
  (* Add same terminator as original rom: *)
  data.(len) <- (Char.code '\n');
  data.(len+1) <- 0; 
  { data; size = len + 2}


(* Read a byte from rom at a given address *)
let read (rom : t) (addr: int) : int * bool = 
  if addr < 0 || addr > Array.length rom.data then
    (0, false)
  else 
    let byte = rom.data.(addr) in
    (byte, byte<>0)
