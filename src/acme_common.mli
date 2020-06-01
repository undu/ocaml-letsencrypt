val letsencrypt_production_url : Uri.t

val letsencrypt_staging_url : Uri.t

type json = Yojson.Basic.t

val json_to_string : ?comma:string -> ?colon:string -> json -> string

module Directory : sig
  (** ACME json data types, as defined in RFC 8555 *)

  type meta = {
    terms_of_service : Uri.t option;
    website : Uri.t option;
    caa_identities : string list option;
  }

  val pp_meta : meta Fmt.t

  type t = {
    new_nonce : Uri.t;
    new_account : Uri.t;
    new_order : Uri.t;
    new_authz : Uri.t option;
    revoke_cert : Uri.t;
    key_change : Uri.t;
    meta : meta option;
  }

  val pp : t Fmt.t

  val decode : string -> (t, [> `Msg of string ]) result
end

module Account : sig
  type t = {
    account_status : [ `Valid | `Deactivated | `Revoked ];
    contact : string list option;
    terms_of_service_agreed : bool option;
    orders : Uri.t list;
    initial_ip : string option;
    created_at : Ptime.t option;
  }

  val pp : t Fmt.t

  val decode : string -> (t, [> `Msg of string ]) result
end

type id_type = [ `Dns ]

module Order : sig
  type t = {
    order_status : [ `Pending | `Ready | `Processing | `Valid | `Invalid ];
    expires : Ptime.t option;
    identifiers : (id_type * string) list;
    not_before : Ptime.t option;
    not_after : Ptime.t option;
    error : json option;
    authorizations : Uri.t list;
    finalize : Uri.t;
    certificate : Uri.t option;
  }

  val pp : t Fmt.t

  val decode : string -> (t, [> `Msg of string ]) result
end

module Challenge : sig
  type typ = [ `Dns | `Http | `Alpn ]

  val pp_typ : typ Fmt.t

  type t = {
    challenge_typ : typ;
    url : Uri.t;
    challenge_status : [ `Pending | `Processing | `Valid | `Invalid ];
    token : string;
    validated : Ptime.t option;
    error : json option;
  }

  val pp : t Fmt.t
end

module Authorization : sig
  type t = {
    identifier : id_type * string;
    authorization_status : [ `Pending | `Valid | `Invalid | `Deactivated | `Expired | `Revoked ];
    expires : Ptime.t option;
    challenges : Challenge.t list;
    wildcard : bool;
  }

  val pp : t Fmt.t

  val decode : string -> (t, [> `Msg of string ]) result
end

module Error : sig
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

  val pp : t Fmt.t

  val decode : string -> (t, [> `Msg of string ]) result
end
