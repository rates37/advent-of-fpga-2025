open! Hardcaml  
open! Signal

module Make (Cfg: Config.S)  = struct
  module Decoder = Decoder_fsm.Make(Cfg)
  module Checker = Region_checker.Make(Cfg)


  module I = struct
    type 'a t = {
      clock: 'a;
      clear: 'a;
      rom_data: 'a [@bits 8];
      rom_valid: 'a;
    }
    [@@deriving hardcaml]
  end

  module O = struct
    type 'a t = {
      rom_addr: 'a [@bits Cfg.rom_addr_width];
      result: 'a [@bits 16];
      done_: 'a;
    }
    [@@deriving hardcaml]
  end

  let create (scope: Scope.t) (i: Signal.t I.t) = 
    let open I in 
    let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
    let valid_count = Always.Variable.reg spec ~enable:vdd ~width:16 in
    let valid_count_v = Always.Variable.value valid_count in

    (* Instantiate decoder: *)
    let decoder_out = Decoder.create scope
      {
        Decoder.I.
        clock = i.clock;
        clear = i.clear;
        rom_data = i.rom_data;
        rom_valid = i.rom_valid;
      }
    in


    (* Instantiate region checker: *)
    let checker_out = Checker.create
      {
        Checker.
        shape_hash_counts = decoder_out.shape_hash_counts;
        region_width = decoder_out.region_width;
        region_height = decoder_out.region_height;
        region_counts = decoder_out.region_counts;
      }
    in
    
    Always.(compile [
      when_ decoder_out.region_valid [
        when_ checker_out.region_valid [
          valid_count <-- valid_count_v +:. 1;
        ];
      ];
    ]);

    {
      O.
      rom_addr = decoder_out.rom_addr;
      result = valid_count_v;
      done_ = decoder_out.done_;
    }
  let hierarcy (scope: Scope.t) (input: Signal.t I.t) = 
    let module H = Hierarchy.In_scope (I) (O) in
    H.hierarchical ~scope ~name:"day12_core" create input
end

module Default = Make(Config.Default)
