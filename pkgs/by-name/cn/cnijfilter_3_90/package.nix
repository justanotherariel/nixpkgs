{
  stdenv,
  lib,
  fetchzip,
  autoconf,
  automake,
  libtool,
  cups,
  popt,
  libtiff,
  libpng,
  ghostscript,
  glib,
  libxml2,
}:

/*
  this derivation is basically just a transcription of the rpm .spec
  file included in the tarball
*/

let
  arch =
    if stdenv.hostPlatform.system == "x86_64-linux" then
      "64"
    else if stdenv.hostPlatform.system == "i686-linux" then
      "32"
    else
      throw "Unsupported system ${stdenv.hostPlatform.system}";

in
stdenv.mkDerivation {
  pname = "cnijfilter";

  /*
    important note about versions: cnijfilter packages seem to use
    versions in a non-standard way.  the version indicates which
    printers are supported in the package.  so this package should
    not be "upgraded" in the usual way.

    instead, if you want to include another version supporting your
    printer, you should try to abstract out the common things (which
    should be pretty much everything except the version and the 'pr'
    and 'pr_id' values to loop over).
  */
  version = "3.90";

  src = fetchzip {
    url = "http://gdlp01.c-wss.com/gds/1/0100005171/01/cnijfilter-source-3.90-1.tar.gz";
    sha256 = "sha256-86T9DbKcXjZJxsTRwNoipG40LiZ4lCtET2VOc7Gl7Po=";
  };

  nativeBuildInputs = [
    autoconf
    automake
  ];
  buildInputs = [
    libtool
    cups
    popt
    libtiff
    libpng
    ghostscript
    glib
    libxml2
  ];

  env.NIX_CFLAGS_COMPILE = " -std=gnu90";

  # patches from https://github.com/tokiclover/bar-overlay/tree/master/net-print/cnijfilter
  patches = [
    ./patches/cnijfilter-3.20-4-ppd.patch
    ./patches/cnijfilter-3.80-1-cups-1.6.patch
    ./patches/cnijfilter-3.80-5-abi_x86_32.patch
    ./patches/cnijfilter-3.80-6-cups-1.6.patch
    ./patches/cnijfilter-3.90-6-headers.patch
    ./patches/cnijfilter-3.90-7-make.patch
  ];

  postPatch = ''
    sed -i "s|/usr/lib/cups/backend|$out/lib/cups/backend|" backend/src/Makefile.am;
    sed -i "s|/usr/lib/cups/backend|$out/lib/cups/backend|" backendnet/backend/Makefile.am;
    sed -i "s|/usr|$out|" backend/src/cnij_backend_common.c;
    sed -i "s|/usr/bin|${ghostscript}/bin|" pstocanonij/filter/pstocanonij.c;
  '';

  configurePhase = ''
    cd libs
    ./autogen.sh --prefix=$out

    cd ../cngpij
    ./autogen.sh --prefix=$out --enable-progpath=$out/bin

    cd ../cngpijmnt
    ./autogen.sh --prefix=$out --enable-progpath=$out/bin

    cd ../pstocanonij
    ./autogen.sh --prefix=$out --enable-progpath=$out/bin

    cd ../backend
    ./autogen.sh --prefix=$out

    cd ../backendnet
    ./autogen.sh --prefix=$out --enable-libpath=$out/lib/bjlib --enable-progpath=$out/bin

    cd ..;
  '';

  preInstall = ''
    mkdir -p $out/bin $out/lib/cups/filter $out/share/cups/model;
  '';

  postInstall = ''
    set -o xtrace
    for pr in e610 mx390 mx450 mx520 mx720 mx920; do
      cd ppd;
      ./autogen.sh --prefix=$out --program-suffix=$pr
      make clean;
      make;
      make install;

      cd ../cnijfilter;
      ./autogen.sh --prefix=$out --program-suffix=$pr --enable-libpath=/var/lib/cups/path/lib/bjlib --enable-binpath=$out/bin;
      make clean;
      make;
      make install;

      cd ..;
    done;

    mkdir -p $out/lib/bjlib;
    for pr_id in 416 417 418 419 420 421; do
      install -c -m 755 $pr_id/database/* $out/lib/bjlib;
      install -c -s -m 755 $pr_id/libs_bin${arch}/*.so.* $out/lib;
    done;

    pushd $out/lib;
    for so_file in *.so.*; do
      ln -s $so_file ''${so_file/.so.*/}.so;
      patchelf --set-rpath $out/lib $so_file;
    done;
    popd;
  '';

  /*
    the tarball includes some pre-built shared libraries.  we run
    'patchelf --set-rpath' on them just a few lines above, so that
    they can find each other.  but that's not quite enough.  some of
    those libraries load each other in non-standard ways -- they
    don't list each other in the DT_NEEDED section.  so, if the
    standard 'patchelf --shrink-rpath' (from
    pkgs/development/tools/misc/patchelf/setup-hook.sh) is run on
    them, it undoes the --set-rpath.  this prevents that.
  */
  dontPatchELF = true;

  meta = with lib; {
    description = "Canon InkJet printer drivers for the E610, MX390, MX450, MX520, MX720, and MX920 series.";
    homepage = "https://www.canon.at/support/consumer/products/printers/pixma/mx-series/mx925.html?type=drivers&os=Linux%20(64-bit)";
    sourceProvenance = with sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    license = licenses.unfree;
    platforms = platforms.linux;
    maintainers = with maintainers; [ justanotherariel ];
  };
}
