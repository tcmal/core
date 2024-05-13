{ lib, stdenv, fetchurl, perl, gitUpdater }:

stdenv.mkDerivation rec {
  pname = "nasm";
  version = "2.16.02";

  src = fetchurl {
    url =
      "https://www.nasm.us/pub/nasm/releasebuilds/${version}/${pname}-${version}.tar.xz";
    sha256 = "sha256-HhuULqiPIu2uiWWeFb4m+gJ+rgdH9RQTVA9S1OrEeQ0=";
  };

  nativeBuildInputs = [ perl ];

  enableParallelBuilding = true;

  doCheck = true;

  checkPhase = ''
    runHook preCheck

    make golden
    make test

    runHook postCheck
  '';

  passthru.updateScript = gitUpdater {
    url = "https://github.com/netwide-assembler/nasm.git";
    rev-prefix = "nasm-";
    ignoredVersions = "rc.*";
  };

  meta = with lib; {
    homepage = "https://www.nasm.us/";
    description =
      "An 80x86 and x86-64 assembler designed for portability and modularity";
    platforms = platforms.unix;
    maintainers = with maintainers; [ pSub willibutz ];
    license = licenses.bsd2;
  };
}
