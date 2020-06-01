open Rresult.R.Infix
open Astring

let letsencrypt_production_url =
  Uri.of_string "https://acme-v02.api.letsencrypt.org/directory"

let letsencrypt_staging_url =
  Uri.of_string "https://acme-staging-v02.api.letsencrypt.org/directory"

module J = Yojson.Basic

type json = J.t

(* Serialize a json object without having spaces around. Dammit Yojson. *)
(* XXX. I didn't pay enough attention on escaping.
 * It is possible that this is okay; however, our encodings are nice. *)
(* NOTE: hannes thinks that Json.to_string (`String {|foo"bar|}) looks suspicious *)
let rec json_to_string ?(comma = ",") ?(colon = ":") : J.t -> string = function
  | `Null -> ""
  | `String s -> Printf.sprintf {|"%s"|} (String.Ascii.escape s)
  | `Bool b -> if b then "true" else "false"
  | `Float f -> string_of_float f
  | `Int i -> string_of_int i
  | `List l ->
    let s = List.map (json_to_string ~comma ~colon) l in
     "[" ^ (String.concat ~sep:comma s) ^ "]"
  | `Assoc a ->
    let serialize_pair (key, value) =
      Printf.sprintf {|"%s"%s%s|} key colon (json_to_string ~comma ~colon value)
    in
    let s = List.map serialize_pair a in
    Printf.sprintf {|{%s}|} (String.concat ~sep:comma s)

let of_string s =
  try Ok (J.from_string s) with
    Yojson.Json_error str -> Error (`Msg str)

let err_msg typ name json =
  Rresult.R.error_msgf "couldn't find %s %s in %s" typ name (J.to_string json)

(* decoders *)
let string_val key json =
  match J.Util.member key json with
  | `String s -> Ok s
  | _ -> err_msg "string" key json

let opt_string_val key json =
  match J.Util.member key json with
  | `String s -> Ok (Some s)
  | `Null -> Ok None
  | _ -> err_msg "opt_string" key json

let assoc_val key json =
  match J.Util.member key json with
  | `Assoc _ | `Null as x -> Ok x
  | _ -> err_msg "assoc" key json

let list_val key json =
  match J.Util.member key json with
  | `List l -> Ok l
  | _ -> err_msg "list" key json

let opt_string_list key json =
  match J.Util.member key json with
  | `List l ->
    let xs =
      List.fold_left
        (fun acc -> function `String s -> s :: acc | _ -> acc)
        [] l
    in
    Ok (Some xs)
  | `Null -> Ok None
  | _ -> err_msg "string list" key json

let opt_bool key json =
  match J.Util.member key json with
  | `Bool b -> Ok (Some b)
  | `Null -> Ok None
  | _ -> err_msg "opt bool" key json

let decode_ptime str =
  match Ptime.of_rfc3339 str with
  | Ok (ts, _, _) -> Ok ts
  | Error `RFC3339 (_, err) ->
    Rresult.R.error_msgf "couldn't parse %s as rfc3339 %a"
      str Ptime.pp_rfc3339_error err

let maybe f = function
  | None -> Ok None
  | Some s -> f s >>| fun s' -> Some s'

let uri s = Ok (Uri.of_string s)

module Directory = struct
  type meta = {
    terms_of_service : Uri.t option;
    website : Uri.t option;
    caa_identities : string list option;
    (* external_accoutn_required *)
  }

  let pp_meta ppf { terms_of_service ; website ; caa_identities } =
    Fmt.pf ppf "terms of service: %a@,website %a@,caa identities %a"
      Fmt.(option ~none:(unit "no tos") Uri.pp_hum) terms_of_service
      Fmt.(option ~none:(unit "no website") Uri.pp_hum) website
      Fmt.(option ~none:(unit "no CAA") (list ~sep:(unit ", ") string))
      caa_identities

  let meta_of_json = function
    | `Assoc _ as json ->
      opt_string_val "termsOfService" json >>= maybe uri >>= fun terms_of_service ->
      opt_string_val "website" json >>= maybe uri >>= fun website ->
      opt_string_list "caaIdentities" json >>| fun caa_identities ->
      Some { terms_of_service ; website ; caa_identities }
    | _ -> Ok None

  type t = {
    new_nonce : Uri.t;
    new_account : Uri.t;
    new_order : Uri.t;
    new_authz : Uri.t option;
    revoke_cert : Uri.t;
    key_change : Uri.t;
    meta : meta option;
  }

  let pp ppf dir =
    Fmt.pf ppf "new nonce %a@,new account %a@,new order %a@,new authz %a@,revoke cert %a@,key change %a@,meta %a"
      Uri.pp_hum dir.new_nonce Uri.pp_hum dir.new_account Uri.pp_hum dir.new_order
      Fmt.(option ~none:(unit "no authz") Uri.pp_hum) dir.new_authz
      Uri.pp_hum dir.revoke_cert Uri.pp_hum dir.key_change
      Fmt.(option ~none:(unit "no meta") pp_meta) dir.meta

  let decode s =
    of_string s >>= fun json ->
    string_val "newNonce" json >>= uri >>= fun new_nonce ->
    string_val "newAccount" json >>= uri >>= fun new_account ->
    string_val "newOrder" json >>= uri >>= fun new_order ->
    opt_string_val "newAuthz" json >>= maybe uri >>= fun new_authz ->
    string_val "revokeCert" json >>= uri >>= fun revoke_cert ->
    string_val "keyChange" json >>= uri >>= fun key_change ->
    assoc_val "meta" json >>= meta_of_json >>| fun meta ->
    { new_nonce ; new_account ; new_order ; new_authz ; revoke_cert ;
      key_change ; meta }
end

module Account = struct
  type t = {
    account_status : [ `Valid | `Deactivated | `Revoked ];
    contact : string list option;
    terms_of_service_agreed : bool option;
    (* externalAccountBinding *)
    orders : Uri.t list;
    initial_ip : string option;
    created_at : Ptime.t option;
  }

  let pp_status ppf s =
    Fmt.string ppf (match s with
        | `Valid -> "valid"
        | `Deactivated -> "deactivated"
        | `Revoked -> "revoked")

  let pp ppf a =
    Fmt.pf ppf "status %a@,contact %a@,terms of service agreed %a@,orders %a@,initial IP %a@,created %a"
      pp_status a.account_status
      Fmt.(option ~none:(unit "no contact") (list ~sep:(unit ", ") string))
      a.contact
      Fmt.(option ~none:(unit "unknown") bool) a.terms_of_service_agreed
      Fmt.(list ~sep:(unit ", ") Uri.pp_hum) a.orders
      Fmt.(option ~none:(unit "unknown") string) a.initial_ip
      Fmt.(option ~none:(unit "unknown") (Ptime.pp_rfc3339 ())) a.created_at

  let status_of_string = function
    | "valid" -> Ok `Valid
    | "deactivated" -> Ok `Deactivated
    | "revoked" -> Ok `Revoked
    | s -> Rresult.R.error_msgf "unknown account status %s" s

  (* "it's fine to not have a 'required' orders array" (in contrast to 8555)
     and seen in the wild when creating an account, or retrieving the account url
     of a key, or even fetching the account url. all with an account that never
     ever did an order... it seems to be a discrepancy from LE servers and
     RFC 8555 *)
  (* https://github.com/letsencrypt/boulder/blob/master/docs/acme-divergences.md
     or https://github.com/letsencrypt/boulder/issues/3335 contains more
     information *)
  let decode str =
    of_string str >>= fun json ->
    string_val "status" json >>= status_of_string >>= fun account_status ->
    opt_string_list "contact" json >>= fun contact ->
    opt_bool "termsOfServiceAgreed" json >>= fun terms_of_service_agreed ->
    (opt_string_list "orders" json >>= function
      | None -> Ok []
      | Some orders -> Ok (List.map Uri.of_string orders)) >>= fun orders ->
    opt_string_val "initialIp" json >>= fun initial_ip ->
    opt_string_val "createdAt" json >>= maybe decode_ptime >>| fun created_at ->
    { account_status ; contact ; terms_of_service_agreed ; orders ; initial_ip ; created_at }
end

type id_type = [ `Dns ]

let pp_id_type ppf = function `Dns -> Fmt.string ppf "dns"

let pp_id = Fmt.(pair ~sep:(unit " - ") pp_id_type string)

let id_type_of_string = function
  | "dns" -> Ok `Dns
  | s -> Rresult.R.error_msgf "only DNS typ is supported, got %s" s

let decode_id json =
  string_val "type" json >>= id_type_of_string >>= fun typ ->
  string_val "value" json >>| fun id ->
  (typ, id)

let decode_ids ids =
  List.fold_left (fun acc json_id ->
      acc >>= fun acc ->
      decode_id json_id >>| fun id ->
      id :: acc)
    (Ok []) ids

module Order = struct
  type t = {
    order_status : [ `Pending | `Ready | `Processing | `Valid | `Invalid ];
    expires : Ptime.t option; (* required if order_status = pending | valid *)
    identifiers : (id_type * string) list;
    not_before : Ptime.t option;
    not_after : Ptime.t option;
    error : json option; (* "structured as problem document, RFC 7807" *)
    authorizations : Uri.t list;
    finalize : Uri.t;
    certificate : Uri.t option;
  }

  let pp_status ppf s =
    Fmt.string ppf (match s with
        | `Pending -> "pending"
        | `Ready -> "ready"
        | `Processing -> "processing"
        | `Valid -> "valid"
        | `Invalid -> "invalid")

  let pp ppf o =
    Fmt.pf ppf "status %a@,expires %a@,identifiers %a@,not_before %a@,not_after %a@,error %a@,authorizations %a@,finalize %a@,certificate %a"
      pp_status o.order_status
      Fmt.(option ~none:(unit "no") (Ptime.pp_rfc3339 ())) o.expires
      Fmt.(list ~sep:(unit ", ") pp_id) o.identifiers
      Fmt.(option ~none:(unit "no") (Ptime.pp_rfc3339 ())) o.not_before
      Fmt.(option ~none:(unit "no") (Ptime.pp_rfc3339 ())) o.not_after
      Fmt.(option ~none:(unit "no error") J.pp) o.error
      Fmt.(list ~sep:(unit ", ") Uri.pp_hum) o.authorizations
      Uri.pp_hum o.finalize
      Fmt.(option ~none:(unit "no") Uri.pp_hum) o.certificate

  let status_of_string = function
    | "pending" -> Ok `Pending
    | "ready" -> Ok `Ready
    | "processing" -> Ok `Processing
    | "valid" -> Ok `Valid
    | "invalid" -> Ok `Invalid
    | s -> Rresult.R.error_msgf "unknown order status %s" s


  let decode str =
    of_string str >>= fun json ->
    string_val "status" json >>= status_of_string >>= fun order_status ->
    opt_string_val "expires" json >>= maybe decode_ptime >>= fun expires ->
    list_val "identifiers" json >>= decode_ids >>= fun identifiers ->
    opt_string_val "notBefore" json >>= maybe decode_ptime >>= fun not_before ->
    opt_string_val "notAfter" json >>= maybe decode_ptime >>= fun not_after ->
    (match J.Util.member "error" json with `Null -> Ok None | x -> Ok (Some x)) >>= fun error ->
    (opt_string_list "authorizations" json >>= function
      | None -> Error (`Msg "no authorizations found in order")
      | Some auths -> Ok (List.map Uri.of_string auths)) >>= fun authorizations ->
    string_val "finalize" json >>= uri >>= fun finalize ->
    opt_string_val "certificate" json >>= maybe uri >>| fun certificate ->
    { order_status ; expires ; identifiers ; not_before ; not_after ; error ;
      authorizations ; finalize ; certificate }
end

module Challenge = struct
  type typ = [ `Dns | `Http | `Alpn ]

  let pp_typ ppf t =
    Fmt.string ppf (match t with `Dns -> "DNS" | `Http -> "HTTP" | `Alpn -> "ALPN")

  let typ_of_string = function
    | "tls-alpn-01" -> Ok `Alpn
    | "http-01" -> Ok `Http
    | "dns-01" -> Ok `Dns
    | s -> Rresult.R.error_msgf "unknown challenge typ %s" s

  (* turns out, the only interesting ones are dns, http, alpn *)
  (* all share the same style *)
  type t = {
    challenge_typ : typ;
    url : Uri.t;
    challenge_status : [ `Pending | `Processing | `Valid | `Invalid ];
    token : string;
    validated : Ptime.t option;
    error : json option;
  }

  let pp_status ppf s =
    Fmt.string ppf (match s with
        | `Pending -> "pending"
        | `Processing -> "processing"
        | `Valid -> "valid"
        | `Invalid -> "invalid")

  let pp ppf c =
    Fmt.pf ppf "status %a@,typ %a@,token %s@,url %a@,validated %a@,error %a"
      pp_status c.challenge_status
      pp_typ c.challenge_typ
      c.token
      Uri.pp_hum c.url
      Fmt.(option ~none:(unit "no") (Ptime.pp_rfc3339 ())) c.validated
      Fmt.(option ~none:(unit "no error") J.pp) c.error

  let status_of_string = function
    | "pending" -> Ok `Pending
    | "processing" -> Ok `Processing
    | "valid" -> Ok `Valid
    | "invalid" -> Ok `Invalid
    | s -> Rresult.R.error_msgf "unknown order status %s" s

  let decode json =
    string_val "type" json >>= typ_of_string >>= fun challenge_typ ->
    string_val "status" json >>= status_of_string >>= fun challenge_status ->
    string_val "url" json >>= uri >>= fun url ->
    (* in all three challenges, it's b64 url encoded (but the raw value never used) *)
    (* they MUST >= 128bit entropy, and not have any trailing = *)
    string_val "token" json >>= fun token ->
    opt_string_val "validated" json >>= maybe decode_ptime >>= fun validated ->
    (match J.Util.member "error" json with `Null -> Ok None | x -> Ok (Some x)) >>| fun error ->
    { challenge_typ ; challenge_status ; url ; token ; validated ; error }
end

module Authorization = struct
  type t = {
    identifier : id_type * string;
    authorization_status : [ `Pending | `Valid | `Invalid | `Deactivated | `Expired | `Revoked ];
    expires : Ptime.t option;
    challenges : Challenge.t list;
    wildcard : bool;
  }

  let pp_status ppf s =
    Fmt.string ppf (match s with
        | `Pending -> "pending"
        | `Valid -> "valid"
        | `Invalid -> "invalid"
        | `Deactivated -> "deactivated"
        | `Expired -> "expired"
        | `Revoked -> "revoked")

  let pp ppf a =
    Fmt.pf ppf "status %a@,identifier %a@,expires %a@,challenges %a@,wildcard %a"
      pp_status a.authorization_status pp_id a.identifier
      Fmt.(option ~none:(unit "no") (Ptime.pp_rfc3339 ())) a.expires
      Fmt.(list ~sep:(unit ",") Challenge.pp) a.challenges
      Fmt.bool a.wildcard

  let status_of_string = function
    | "pending" -> Ok `Pending
    | "valid" -> Ok `Valid
    | "invalid" -> Ok `Invalid
    | "deactivated" -> Ok `Deactivated
    | "expired" -> Ok `Expired
    | "revoked" -> Ok `Revoked
    | s -> Rresult.R.error_msgf "unknown order status %s" s

  let decode str =
    of_string str >>= fun json ->
    assoc_val "identifier" json >>= decode_id >>= fun identifier ->
    string_val "status" json >>= status_of_string >>= fun authorization_status ->
    opt_string_val "expires" json >>= maybe decode_ptime >>= fun expires ->
    list_val "challenges" json >>= fun challenges ->
    let challenges =
      (* be modest in what you receive - there may be other challenges in the future *)
      List.fold_left (fun acc json ->
          match Challenge.decode json with
          | Error `Msg err ->
            Logs.warn (fun m -> m "ignoring challenge %a: parse error %s" J.pp json err);
            acc
          | Ok c -> c :: acc) [] challenges
    in
    (* TODO "MUST be present and true for orders containing a DNS identifier with wildcard. for others, it MUST be absent" *)
    (opt_bool "wildcard" json >>| function None -> false | Some v -> v) >>| fun wildcard ->
    { identifier ; authorization_status ; expires ; challenges ; wildcard }
end

module Error = struct
  (* from http://www.iana.org/assignments/acme urn registry *)
  type t = {
    err_typ : [
      | `Account_does_not_exist | `Already_revoked | `Bad_csr | `Bad_nonce
      | `Bad_public_key | `Bad_revocation_reason | `Bad_signature_algorithm
      | `CAA | `Connection | `DNS | `External_account_required
      | `Incorrect_response | `Invalid_contact | `Malformed | `Order_not_ready
      | `Rate_limited | `Rejected_identifier | `Server_internal | `TLS
      | `Unauthorized | `Unsupported_contact | `Unsupported_identifier
      | `User_action_required
    ];
    detail : string
  }

  let err_typ_to_string = function
    | `Account_does_not_exist -> "The request specified an account that does not exist"
    | `Already_revoked -> "The request specified a certificate to be revoked that has already been revoked"
    | `Bad_csr -> "The CSR is unacceptable (e.g., due to a short key)"
    | `Bad_nonce -> "The client sent an unacceptable anti-replay nonce"
    | `Bad_public_key -> "The JWS was signed by a public key the server does not support"
    | `Bad_revocation_reason -> "The revocation reason provided is not allowed by the server"
    | `Bad_signature_algorithm -> "The JWS was signed with an algorithm the server does not support"
    | `CAA -> "Certification Authority Authorization (CAA) records forbid the CA from issuing a certificate"
    (*  | `Compound -> "Specific error conditions are indicated in the 'subproblems' array" *)
    | `Connection -> "The server could not connect to validation target"
    | `DNS -> "There was a problem with a DNS query during identifier validation"
    | `External_account_required -> "The request must include a value for the 'externalAccountBinding' field"
    | `Incorrect_response -> "Response received didn't match the challenge's requirements"
    | `Invalid_contact -> "A contact URL for an account was invalid"
    | `Malformed -> "The request message was malformed"
    | `Order_not_ready -> "The request attempted to finalize an order that is not ready to be finalized"
    | `Rate_limited -> "The request exceeds a rate limit"
    | `Rejected_identifier -> "The server will not issue certificates for the identifier"
    | `Server_internal -> "The server experienced an internal error"
    | `TLS -> "The server received a TLS error during validation"
    | `Unauthorized -> "The client lacks sufficient authorization"
    | `Unsupported_contact -> "A contact URL for an account used an unsupported protocol scheme"
    | `Unsupported_identifier -> "An identifier is of an unsupported type"
    | `User_action_required -> "Visit the 'instance' URL and take actions specified there"

  let pp ppf e =
    Fmt.pf ppf "%s, detail: %s" (err_typ_to_string e.err_typ) e.detail

  let err_typ_of_string str =
    match Astring.String.cut ~sep:"urn:ietf:params:acme:error:" str with
    | Some ("", err) ->
      (* from https://www.iana.org/assignments/acme/acme.xhtml (20200209) *)
      begin match err with
        | "accountDoesNotExist" -> Ok `Account_does_not_exist
        | "alreadyRevoked" -> Ok `Already_revoked
        | "badCSR" -> Ok `Bad_csr
        | "badNonce" -> Ok `Bad_nonce
        | "badPublicKey" -> Ok `Bad_public_key
        | "badRevocationReason" -> Ok `Bad_revocation_reason
        | "badSignatureAlgorithm" -> Ok `Bad_signature_algorithm
        | "caa" -> Ok `CAA
        (* | "compound" -> Ok `Compound see 'subproblems' array *)
        | "connection" -> Ok `Connection
        | "dns" -> Ok `DNS
        | "externalAccountRequired" -> Ok `External_account_required
        | "incorrectResponse" -> Ok `Incorrect_response
        | "invalidContact" -> Ok `Invalid_contact
        | "malformed" -> Ok `Malformed
        | "orderNotReady" -> Ok `Order_not_ready
        | "rateLimited" -> Ok `Rate_limited
        | "rejectedIdentifier" -> Ok `Rejected_identifier
        | "serverInternal" -> Ok `Server_internal
        | "tls" -> Ok `TLS
        | "unauthorized" -> Ok `Unauthorized
        | "unsupportedContact" -> Ok `Unsupported_contact
        | "unsupportedIdentifier" -> Ok `Unsupported_identifier
        | "userActionRequired" -> Ok `User_action_required
        | s -> Rresult.R.error_msgf "unknown acme error typ %s" s
      end
    | _ -> Rresult.R.error_msgf "unknown error type %s" str

  let decode str =
    of_string str >>= fun json ->
    string_val "type" json >>= err_typ_of_string >>= fun err_typ ->
    string_val "detail" json >>| fun detail ->
    { err_typ ; detail }
end
