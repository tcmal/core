{ lib
, buildPythonPackage
, fetchPypi
, pythonOlder

# build-system
, flit-core

# tests
, pretend
, pytestCheckHook
}:

let
  packaging = buildPythonPackage rec {
    pname = "packaging";
    version = "24.0";
    pyproject = true;

    disabled = pythonOlder "3.7";

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-64LF4+ViCQdHZuaIW7BLjDigwBXQowA26+fs40yZiek=";
    };

    nativeBuildInputs = [
      flit-core
    ];

    nativeCheckInputs = [
      pytestCheckHook
      pretend
    ];

    pythonImportsCheck = [
      "packaging"
      "packaging.metadata"
      "packaging.requirements"
      "packaging.specifiers"
      "packaging.tags"
      "packaging.version"
    ];

    # Prevent circular dependency with pytest
    doCheck = false;

    passthru.tests = packaging.overridePythonAttrs (_: { doCheck = true; });

    meta = with lib; {
      changelog = "https://github.com/pypa/packaging/blob/${version}/CHANGELOG.rst";
      description = "Core utilities for Python packages";
      downloadPage = "https://github.com/pypa/packaging";
      homepage = "https://packaging.pypa.io/";
      license = with licenses; [ bsd2 asl20 ];
      # maintainers = teams.python.members ++ (with maintainers; [ bennofs ]);
    };
  };
in
packaging
