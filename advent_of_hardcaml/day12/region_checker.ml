open! Hardcaml
open! Signal


module Make (Cfg: Config.S) = struct
  type 'a input = {
    shape_hash_counts: 'a array;
    region_width: 'a;
    region_height: 'a;
    region_counts: 'a array;
  }

  type 'a output = {
    region_valid: 'a;
  }

  let div_by_3 ~(dividend: Signal.t) : Signal.t = 
    let three = of_int ~width:8 3 in
    let rec compute_quotient q r iterations_left = 
      if iterations_left = 0 then q 
      else
        let can_sub = r >=: three in
        let new_r = mux2 can_sub (r -: three) r in
        let new_q = mux2 can_sub (q +:. 1) q in
        compute_quotient new_q new_r (iterations_left - 1)
      in
      compute_quotient (zero 8) dividend 86 (* 255 / 3 = 85 so 86 is max*)
    
  let create (i: Signal.t input) : Signal.t output = 
    let region_area = uresize (uresize i.region_width 8 *: uresize i.region_height 8) 24 in

    let prod count hash = uresize (uresize count 8 *: uresize hash 8) 24 in
    let required_area = 
      let sum = ref (zero 24) in
      for idx = 0 to Cfg.num_shapes-1 do
        sum := !sum +: prod i.region_counts.(idx) i.shape_hash_counts.(idx)
      done;
      !sum
    in 

    let sum_counts = 
      let sum = ref (zero 24) in
      for idx = 0 to Cfg.num_shapes - 1 do
        sum := !sum +: uresize i.region_counts.(idx) 24 
      done;
      !sum
    in 

    let w_div_3 = div_by_3 ~dividend:i.region_width in
    let h_div_3 = div_by_3 ~dividend:i.region_height in
    let max_3x3_blocks = uresize (w_div_3 *: h_div_3) 24 in
    let area_ok = required_area <=: region_area in
    let blocks_ok = sum_counts <=: max_3x3_blocks in

    {region_valid = area_ok &: blocks_ok }
end

module Default = Make(Config.Default)
