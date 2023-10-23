open Register

type init_clear = { ctype : string; init : string; clear : string }
[@@deriving yojson]

type t = { init_clear : init_clear list } [@@deriving yojson]

let default = { init_clear = [] }

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
