open OUnit2

let testkey_pem = "
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA4xgZ3eRPkwoRvy7qeRUbmMDe0V+xH9eWLdu0iheeLlrmD2mq
WXfP9IeSKApbn34g8TuAS9g5zhq8ELQ3kmjr+KV86GAMgI6VAcGlq3QrzpTCf/30
Ab7+zawrfRaFONa1HwEzPY1KHnGVkxJc85gNkwYI9SY2RHXtvln3zs5wITNrdosq
EXeaIkVYBEhbhNu54pp3kxo6TuWLi9e6pXeWetEwmlBwtWZlPoib2j3TxLBksKZf
oyFyek380mHgJAumQ/I2fjj98/97mk3ihOY4AgVdCDj1z/GCoZkG5Rq7nbCGyosy
KWyDX00Zs+nNqVhoLeIvXC4nnWdJMZ6rogxyQQIDAQABAoIBACIEZTOI1Kao9nmV
9IeIsuaR1Y61b9neOF/MLmIVIZu+AAJFCMB4Iw11FV6sFodwpEyeZhx2WkpWVN+H
r19eGiLX3zsL0DOdqBJoSIHDWCCMxgnYJ6nvS0nRxX3qVrBp8R2g12Ub+gNPbmFm
ecf/eeERIVxfifd9VsyRu34eDEvcmKFuLYbElFcPh62xE3x12UZvV/sN7gXbawpP
G+w255vbE5MoaKdnnO83cTFlcHvhn24M/78qP7Te5OAeelr1R89kYxQLpuGe4fbS
zc6E3ym5Td6urDetGGrSY1Eu10/8sMusX+KNWkm+RsBRbkyKq72ks/qKpOxOa+c6
9gm+Y8ECgYEA/iNUyg1ubRdH11p82l8KHtFC1DPE0V1gSZsX29TpM5jS4qv46K+s
8Ym1zmrORM8x+cynfPx1VQZQ34EYeCMIX212ryJ+zDATl4NE0I4muMvSiH9vx6Xc
7FmhNnaYzPsBL5Tm9nmtQuP09YEn8poiOJFiDs/4olnD5ogA5O4THGkCgYEA5MIL
qWYBUuqbEWLRtMruUtpASclrBqNNsJEsMGbeqBJmoMxdHeSZckbLOrqm7GlMyNRJ
Ne/5uWRGSzaMYuGmwsPpERzqEvYFnSrpjW5YtXZ+JtxFXNVfm9Z1gLLgvGpOUCIU
RbpoDckDe1vgUuk3y5+DjZihs+rqIJ45XzXTzBkCgYBWuf3segruJZy5rEKhTv+o
JqeUvRn0jNYYKFpLBeyTVBrbie6GkbUGNIWbrK05pC+c3K9nosvzuRUOQQL1tJbd
4gA3oiD9U4bMFNr+BRTHyZ7OQBcIXdz3t1qhuHVKtnngIAN1p25uPlbRFUNpshnt
jgeVoHlsBhApcs5DUc+pyQKBgDzeHPg/+g4z+nrPznjKnktRY1W+0El93kgi+J0Q
YiJacxBKEGTJ1MKBb8X6sDurcRDm22wMpGfd9I5Cv2v4GsUsF7HD/cx5xdih+G73
c4clNj/k0Ff5Nm1izPUno4C+0IOl7br39IPmfpSuR6wH/h6iHQDqIeybjxyKvT1G
N0rRAoGBAKGD+4ZI/E1MoJ5CXB8cDDMHagbE3cq/DtmYzE2v1DFpQYu5I4PCm5c7
EQeIP6dZtv8IMgtGIb91QX9pXvP0aznzQKwYIA8nZgoENCPfiMTPiEDT9e/0lObO
9XWsXpbSTsRPj0sv1rB+UzBJ0PgjK4q2zOF0sNo7b1+6nlM3BWPx
-----END RSA PRIVATE KEY-----
" |> Cstruct.of_string

module Json = Yojson.Basic

let jws_foo () =
  let maybe_key = X509.Encoding.Pem.Private_key.of_pem_cstruct testkey_pem in
  let priv_key = match maybe_key with
    | [`RSA skey] -> skey
    (* XXX: more appropriate exception? This code is never executed anyway. *)
    | _ -> raise End_of_file in
  let data  = {|{"Msg":"Hello JWS"}|} in
  let nonce = "nonce" in
  let jws = Jws.encode priv_key data nonce |> Json.from_string in
  jws

let test_protected test_ctx =
  let jws = jws_foo () in
  let expected =
      "eyJhbGciOiJSUzI1NiIsImp3ayI6eyJlIjoiQVFBQiIsImt0eSI6" ^
      "IlJTQSIsIm4iOiI0eGdaM2VSUGt3b1J2eTdxZVJVYm1NRGUwVi14" ^
      "SDllV0xkdTBpaGVlTGxybUQybXFXWGZQOUllU0tBcGJuMzRnOFR1" ^
      "QVM5ZzV6aHE4RUxRM2ttanItS1Y4NkdBTWdJNlZBY0dscTNRcnpw" ^
      "VENmXzMwQWI3LXphd3JmUmFGT05hMUh3RXpQWTFLSG5HVmt4SmM4" ^
      "NWdOa3dZSTlTWTJSSFh0dmxuM3pzNXdJVE5yZG9zcUVYZWFJa1ZZ" ^
      "QkVoYmhOdTU0cHAza3hvNlR1V0xpOWU2cFhlV2V0RXdtbEJ3dFda" ^
      "bFBvaWIyajNUeExCa3NLWmZveUZ5ZWszODBtSGdKQXVtUV9JMmZq" ^
      "ajk4Xzk3bWszaWhPWTRBZ1ZkQ0RqMXpfR0NvWmtHNVJxN25iQ0d5" ^
      "b3N5S1d5RFgwMFpzLW5OcVZob0xlSXZYQzRubldkSk1aNnJvZ3h5" ^
      "UVEifSwibm9uY2UiOiJub25jZSJ9" in
  match Json.Util.member "protected" jws with
    | `String got -> assert_equal got expected
    | _ -> assert_failure "Cannot get field \"protected\"."

let test_payload test_ctx =
  let jws = jws_foo () in
  let expected = "eyJNc2ciOiJIZWxsbyBKV1MifQ" in
  match Json.Util.member "payload" jws with
  | `String got -> assert_equal got expected
  | _ -> assert_failure "Cannot get field \"payload\"."

let test_signature test_ctx =
  let jws = jws_foo () in
  let expected =
    "eAGUikStX_UxyiFhxSLMyuyBcIB80GeBkFROCpap2sW3EmkU_ggF" ^
    "knaQzxrTfItICSAXsCLIquZ5BbrSWA_4vdEYrwWtdUj7NqFKjHRa" ^
    "zpLHcoR7r1rEHvkoP1xj49lS5fc3Wjjq8JUhffkhGbWZ8ZVkgPdC" ^
    "4tMBWiQDoth-x8jELP_3LYOB_ScUXi2mETBawLgOT2K8rA0Vbbmx" ^
    "hWNlOWuUf-8hL5YX4IOEwsS8JK_TrTq5Zc9My0zHJmaieqDV0UlP" ^
    "k0onFjPFkGm7MrPSgd0MqRG-4vSAg2O4hDo7rKv4n8POjjXlNQvM" ^
    "9IPLr8qZ7usYBKhEGwX3yq_eicAwBw" in
  match Json.Util.member "signature" jws with
  | `String got -> assert_equal got expected
  | _ -> assert_failure "Cannot get field \"signature\"."

let all_tests = [
    "test_protected" >:: test_protected;
    "test_payload" >:: test_payload;
    "test_signature" >:: test_signature
  ]