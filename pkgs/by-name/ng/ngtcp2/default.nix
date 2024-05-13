{ lib, stdenv, fetchFromGitHub, cmake, brotli, libev, nghttp3, quictls
, CoreServices, withJemalloc ? false, jemalloc
# for passthru.tests
# , curlHTTP3
}:

stdenv.mkDerivation rec {
  pname = "ngtcp2";
  version = "1.4.0";

  src = fetchFromGitHub {
    owner = "ngtcp2";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-te/kFt7/09QpmkHZ7dJxyKvvxP+mHtIQIgESkJATR38=";
    fetchSubmodules = true;
  };

  outputs = [ "out" "dev" "doc" ];

  nativeBuildInputs = [ cmake ];
  buildInputs = [ brotli libev nghttp3 quictls ]
    ++ lib.optionals stdenv.isDarwin [ CoreServices ]
    ++ lib.optional withJemalloc jemalloc;

  cmakeFlags = [ (lib.cmakeBool "ENABLE_STATIC_LIB" false) ];

  doCheck = true;

  # passthru.tests = {
  #   inherit curlHTTP3;
  # };

  meta = with lib; {
    homepage = "https://github.com/ngtcp2/ngtcp2";
    description =
      "ngtcp2 project is an effort to implement QUIC protocol which is now being discussed in IETF QUICWG for its standardization.";
    license = licenses.mit;
    platforms = platforms.unix;
    maintainers = with maintainers; [ izorkin ];
  };
}
