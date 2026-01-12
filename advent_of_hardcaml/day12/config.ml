module type S = sig
  val num_shapes: int
  val rom_addr_width: int
end

module Default: S = struct
  let num_shapes = 6
  let rom_addr_width = 17
end
