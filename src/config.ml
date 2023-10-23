open Register

type allocation = { ctype : string; init : string; clear : string }
[@@deriving yojson]

type t = { allocations : allocation list } [@@deriving yojson]

let default = { allocations = [] }

let read_config filename =
  let json = Yojson.Safe.from_file filename in
  match of_yojson json with
  | Ok config -> config
  | Error msg -> P.abort "Configuration parsing error: %s" msg

module Config = P.String (struct
  let option_name = "-gen-config"
  let arg_name = "FILE"
  let help = "configuration of the generation"
  let default = ""
end)

let read_config () =
  if Config.is_default () then default else read_config (Config.get ())
