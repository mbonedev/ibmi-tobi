#!/QOpenSys/pkgs/bin/bash
# ****************************************************************************
# Erstellung:  Mai 2026                                                
#              Alessandro Zammataro                                             
# Funktion:    SSH-Script für Azure DevOps Pipeline                      
#              Für das Ausbringen von Merbag IBMi TOBi                   
#
#
# Parameter:   $1 = Zielpfad für die erzeugte RPM-Datei
# ****************************************************************************
inputParam1=$1

#########################################
# 1. Dependency Check
#########################################

echo "🔍 Prüfe benötigte yum Pakete..."

REQUIRED_PACKAGES=(
    rpm-build
    # gcc
    # make
    bash
)

MISSING_PACKAGES=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! rpm -q $pkg >/dev/null 2>&1; then
        echo "❌ Paket fehlt: $pkg"
        MISSING_PACKAGES+=("$pkg")
    else
        echo "✅ Paket vorhanden: $pkg"
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo "📦 Installiere fehlende Pakete: ${MISSING_PACKAGES[*]}"
    # yum -y install "${MISSING_PACKAGES[@]}"
else
    echo "✅ Alle Abhängigkeiten bereits installiert."
fi

#########################################
# 2. Build- und Installationsprozess
#########################################

if [ -n "$inputParam1" ]; then
    cd "$inputParam1"
fi

SRC_DIR="$(pwd)"
RPM_OUTPUT_DIR="$SRC_DIR/rpm"
RPMBUILD_DIR="$SRC_DIR/rpmbuild"
SPEC_FILE="$RPMBUILD_DIR/SPECS/merbag-tobi.spec"
SOURCE_BASENAME=$(basename "$SRC_DIR")
SOURCE_ARCHIVE="merbag-tobi.tar.gz"

VERSION="3.4.0"

echo "✅ Starte RPM Build Prozess für IBM i TOBI..."

# rpmbuild Struktur sicherstellen
echo "📁 Stelle rpmbuild-Verzeichnisstruktur sicher..."
mkdir -p "$RPMBUILD_DIR"
mkdir -p "$RPMBUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
mkdir -p "$RPM_OUTPUT_DIR"

# Tarball erzeugen
echo "📦 Erzeuge Source-Tarball..."
cd "$(dirname "$SRC_DIR")"

# Windows-Zeilenenden (CRLF) in Unix-Zeilenenden (LF) konvertieren
echo "🔄 Konvertiere Zeilenenden (CRLF -> LF)..."
find "$SOURCE_BASENAME/bin" "$SOURCE_BASENAME/src" -type f | while read f; do
    tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

tar -cf "${SOURCE_ARCHIVE%.gz}" "$SOURCE_BASENAME"
gzip -f "${SOURCE_ARCHIVE%.gz}"
mv "$SOURCE_ARCHIVE" "$RPMBUILD_DIR/SOURCES"

# Spec-File erzeugen
echo "📝 Erzeuge Spec-File..."
cat > $SPEC_FILE <<EOF
Name:           merbag-tobi
Version:        $VERSION
Release:        1%{?dist}
Summary:        IBMi Tobi Build Tool
License:        MIT
URL:            https://github.com/mbonedev/ibmi-tobi
Source0:        merbag-tobi.tar.gz

BuildArch:      noarch
BuildRequires:  bash
Requires:       bash

%global __os_install_post %{nil}

%description
IBMi TOBI ist ein CLI-Tool, welches Programmobjekte automatisch umwandelt.

%prep
%setup -q -n $SOURCE_BASENAME

%build

%install
LIBDIR=%{buildroot}/QOpenSys/pkgs/lib/merbag-tobi

# Verzeichnisstruktur anlegen
mkdir -p \$LIBDIR/bin
mkdir -p \$LIBDIR/src/makei/cli
mkdir -p \$LIBDIR/src/mk
mkdir -p \$LIBDIR/src/scripts
mkdir -p %{buildroot}/QOpenSys/pkgs/bin

# bin/
cp bin/makei \$LIBDIR/bin/makei
cp bin/crtfrmstmf \$LIBDIR/bin/crtfrmstmf
chmod 755 \$LIBDIR/bin/makei
chmod 755 \$LIBDIR/bin/crtfrmstmf

# src/makei/
cp src/makei/*.py \$LIBDIR/src/makei/
cp src/makei/cli/*.py \$LIBDIR/src/makei/cli/

# src/mk/
cp src/mk/* \$LIBDIR/src/mk/

# src/scripts/
cp src/scripts/* \$LIBDIR/src/scripts/
chmod 755 \$LIBDIR/src/scripts/*

# Symlinks nach /QOpenSys/pkgs/bin
ln -sf /QOpenSys/pkgs/lib/merbag-tobi/bin/makei %{buildroot}/QOpenSys/pkgs/bin/makei
ln -sf /QOpenSys/pkgs/lib/merbag-tobi/bin/crtfrmstmf %{buildroot}/QOpenSys/pkgs/bin/crtfrmstmf

%files
%dir /QOpenSys/pkgs/lib/merbag-tobi
%dir /QOpenSys/pkgs/lib/merbag-tobi/bin
%dir /QOpenSys/pkgs/lib/merbag-tobi/src
%dir /QOpenSys/pkgs/lib/merbag-tobi/src/makei
%dir /QOpenSys/pkgs/lib/merbag-tobi/src/makei/cli
%dir /QOpenSys/pkgs/lib/merbag-tobi/src/mk
%dir /QOpenSys/pkgs/lib/merbag-tobi/src/scripts
/QOpenSys/pkgs/lib/merbag-tobi/bin/makei
/QOpenSys/pkgs/lib/merbag-tobi/bin/crtfrmstmf
/QOpenSys/pkgs/lib/merbag-tobi/src/makei/*.py
/QOpenSys/pkgs/lib/merbag-tobi/src/makei/cli/*.py
/QOpenSys/pkgs/lib/merbag-tobi/src/mk/*
/QOpenSys/pkgs/lib/merbag-tobi/src/scripts/*
/QOpenSys/pkgs/bin/makei
/QOpenSys/pkgs/bin/crtfrmstmf

%changelog
* Tue Mar 31 2026 Alessandro Zammataro - $VERSION-1
- Automatic build script
EOF

# RPM bauen
echo "🔨 Baue RPM..."
# rpmbuild schreibt Script-Trace (+ ...) auf STDERR; in CI (failOnStdErr) als STDOUT behandeln.
rpmbuild \
  --define "_topdir $RPMBUILD_DIR" \
    --quiet \
    -ba "$SPEC_FILE" \
    2>&1

# RPM in Zielverzeichnis kopieren
echo "📤 Kopiere RPM nach $RPM_OUTPUT_DIR"
find $RPMBUILD_DIR/RPMS -name "merbag-tobi*.rpm" -exec cp {} $RPM_OUTPUT_DIR/ \;

RPM_FILE=$(find $RPM_OUTPUT_DIR -name "merbag-tobi*.rpm" | head -1)

# Installation
# echo "📥 Installiere RPM via yum: $RPM_FILE"
yum erase -y merbag-tobi
yum -y install "$RPM_FILE"

echo "✅ Fertig! TOBI ist nun als 'merbag-tobi' installiert."
