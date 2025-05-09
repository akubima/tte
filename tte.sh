#!/bin/bash

# =========
# IMPORTANT NOTE: Character '|' And ';' is used as a delimiter in this bash script and should not be used in user input or within any data unless the character is a delimiter itself.
# =========

# =========================== GLOBAL VARIABLES DECLARATION ===========================
PATH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH_CERTS_DIR="$PATH_SCRIPT_DIR/.certs"
PATH_SIGNER="$PATH_SCRIPT_DIR/.resources/open-pdf-sign.jar"
PATH_CONFIG_FILE="$PATH_SCRIPT_DIR/.resources/.config"
PATH_LICENSE_FILE="$PATH_SCRIPT_DIR/.resources/LICENSE.html"

UI_WINDOW_SIZE_GENERAL=(800 400)
UI_WINDOW_SIZE_ALERT=(300 100)

SYSTEM_REQUIRED_PACKAGES=(zenity openssl default-jre file poppler-utils)

declare -A DATA_MAP_CERTIFICATES_AVAILABLE
DATA_CERTIFICATES_AVAILABLE=()
# =========================== END OF GLOBAL VARIABLES DECLARATION =====================

# =========================== FUNCTIONS DEFINITION ===========================
FN_Init () {

    # Zenity must be installed to run this script.
    if ! dpkg -s zenity; then
        sudo apt-get install -y zenity || return 1
    fi

    echo "Memeriksa sistem operasi..."

    if ! command -v apt; then
        FN_ShowError "Sistem Operasi Tidak Didukung" "Skrip ini hanya mendukung sistem operasi berbasis Debian/Ubuntu."
        return 1
    fi 

    echo "Memeriksa paket..."

    local MISSING_PACKAGES=()

    for PKG in "${SYSTEM_REQUIRED_PACKAGES[@]}"; do
        if ! dpkg -s "$PKG"; then
            MISSING_PACKAGES+=("$PKG")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then        
        FN_ShowQuestion "Beberapa Paket Tidak Terinstal" "Paket berikut tidak terinstal:\n\n$(printf "%s\n" "${MISSING_PACKAGES[@]}")\n\nUntuk menjalankan skrip ini paket-paket tersebut harus diinstal terlebih dahulu.\nIngin menginstal paket-paket tersebut?"

        [ $? -ne 0 ] && return 1

        echo "Menginstall paket yang hilang..."

        for PKG in "${MISSING_PACKAGES[@]}"; do
            echo "Menginstall $PKG ..."
            sudo apt-get install -y "$PKG" || return 1
        done
    fi

    echo "Memeriksa folder..."
    mkdir -p "$PATH_CERTS_DIR" || return 1

    echo "Memeriksa file konfigurasi..."
    touch "$PATH_CONFIG_FILE" || return 1

    echo "Inisialisasi selesai!"
    
    return 0
}

FN_ReadConfig () {
    local KEY="$1"
    grep "^$KEY=" "$PATH_CONFIG_FILE" | cut -d '=' -f 2
}

FN_WriteConfig () {
    local KEY="$1"
    local VALUE="$2"

    # Jika baris key=... sudah ada maka update nilainya saja.
    if grep -q "^$KEY=" "$PATH_CONFIG_FILE"; then
        sed -i "s|^$KEY=.*|$KEY=$VALUE|" "$PATH_CONFIG_FILE"
    else
        echo "$KEY=$VALUE" >> "$PATH_CONFIG_FILE"
    fi
}

FN_PromptLicense () {
    if [ ! -f "$PATH_LICENSE_FILE" ]; then
        FN_ShowError "" "File informasi lisensi tidak dapat ditemukan!"
        return 1
    fi

    zenity --text-info --title="Persetujuan Lisensi" --filename="$PATH_LICENSE_FILE" --checkbox="Saya menyetujui ketentuan dalam lisensi ini." --html --width=${UI_WINDOW_SIZE_GENERAL[0]} --height=${UI_WINDOW_SIZE_GENERAL[1]}

    if [ $? -eq 0 ]; then
        FN_WriteConfig "LICENSE_AGREED" "TRUE" && return 0 || return 1
    fi

    return 1
}

FN_SelectExistingOrCreateNewCert () {
    zenity --list --radiolist --title="Tentukan Pilihan" --text="Gunakan sertifikat yang ada atau buat baru?" --column="#" --column="Nomor" --column="Pilihan" --print-column=2 --width=${UI_WINDOW_SIZE_GENERAL[0]} --height=${UI_WINDOW_SIZE_GENERAL[1]} "TRUE" 1 "Gunakan sertifikat yang ada" "FALSE" 2 "Buat sertifikat baru"
}

FN_SelectPDFFile () {
    zenity --file-selection --title="Pilih File PDF Untuk Ditandatangani" --file-filter="*.pdf" --width=${UI_WINDOW_SIZE_GENERAL[0]} --height=${UI_WINDOW_SIZE_GENERAL[1]}
}

FN_StorePDFFilePath () {
    local PDF_FILE=$1

    zenity --file-selection --save --confirm-overwrite --title="Pilih Lokasi Penyimpanan Dokumen" --filename="${PDF_FILE%.pdf}-signed.pdf" --file-filter="*.pdf"
}

FN_CheckFileType () {
    local FILE="$1"
    local DESIRED_TYPE="$2"
    local FILE_TYPE=$(file --mime-type -b "$FILE")

    [ "$FILE_TYPE" = "$DESIRED_TYPE" ] && return 0 || return 1
}

FN_ShowQuestion () {
    local TITLE="${1:-"Konfirmasi"}"
    local MESSSAGE="$2"
    local OPTION_TRUE=${3:-"Ya"}
    local OPTION_FALSE=${4:-"Tidak"}

    zenity --question --title="$TITLE" --text="$MESSSAGE" --ok-label="$OPTION_TRUE" --cancel-label="$OPTION_FALSE" --width=${UI_WINDOW_SIZE_ALERT[0]} --height=${UI_WINDOW_SIZE_ALERT[1]}
}

FN_ShowError () {
    local TITLE="${1:-"Terjadi Kesalahan"}"
    local MESSSAGE="${2:-"Terjadi kesalahan yang tidak diketahui."}"

    zenity --error --title="$TITLE" --text="$MESSSAGE" --width=${UI_WINDOW_SIZE_ALERT[0]} --height=${UI_WINDOW_SIZE_ALERT[1]}
}

FN_ShowInfo () {
    local TITLE="${1:-"Informasi"}"
    local MESSSAGE="$2"

    zenity --info --title="$TITLE" --text="$MESSSAGE" --width=${UI_WINDOW_SIZE_ALERT[0]} --height=${UI_WINDOW_SIZE_ALERT[1]}
}

FN_CreateCertificate () {
    local MAN_CN MAN_EMAIL OPS_ORG MAN_COUNTRY FORM_RESULT CONFIG_LAST_CERT_ID CURRENT_CERT_ID CURRENT_CERT_NAME CURRENT_CERT_DIR
    
    # Allowed input characters pattern: 
    #   letters (a-zA-Z),
    #   digits (0-9), 
    #   dot (.), 
    #   hyphen (-), 
    #   at-sign (@), 
    #   and space.
    local ALLOWED_PATTERN="^[-a-zA-Z0-9.@ ]*$"

    while true; do
        FORM_RESULT=$(zenity --forms \
            --title="Buat Sertifikat Baru" \
            --separator="|" \
            --text="Masukkan informasi untuk sertifikat digital:" \
            --width=${UI_WINDOW_SIZE_GENERAL[0]} --height=${UI_WINDOW_SIZE_GENERAL[1]} \
            --add-entry="Nama Lengkap (CN)" \
            --add-entry="Email" \
            --add-entry="Organisasi (O) (opsional)" \
            --add-combo="Negara (C)" \
            --combo-values="ID|AR|AU|BR|CA|CN|FR|DE|IN|IT|JP|MX|RU|SA|ZA|KR|TR|GB|US|EU"
        )

        [ $? -ne 0 ] && return 1

        IFS="|" read -r MAN_CN MAN_EMAIL OPS_ORG MAN_COUNTRY <<< "$FORM_RESULT"

        # === INPUT SANITIZATION ===
        # Hapus spasi di awal dan akhir dari setiap input.
        MAN_CN=$(echo "$MAN_CN" | xargs)
        MAN_EMAIL=$(echo "$MAN_EMAIL" | xargs)
        OPS_ORG=$(echo "$OPS_ORG" | xargs)
        MAN_COUNTRY=$(echo "$MAN_COUNTRY" | xargs)

        if [[ -z "$MAN_CN" || -z "$MAN_EMAIL" || -z "$MAN_COUNTRY" ]]; then
            FN_ShowError "Input Tidak Valid" "Nama Lengkap (CN), Email, dan Negara (C) harus diisi!"
            continue
        fi

        for FIELD in "$MAN_CN" "$MAN_EMAIL" "$OPS_ORG" "$MAN_COUNTRY"; do
            if [[ ! "$FIELD" =~ $ALLOWED_PATTERN ]]; then
                FN_ShowError "Input Tidak Valid" "Input hanya boleh mengandung huruf, angka, titik (.), tanda hubung (-), at-sign (@), dan spasi!\n\nSilakan coba lagi. \n\nKesalahan: $FIELD"
                continue 2
            fi
        done
         # === END OF INPUT SANITIZATION ===

        break
    done

    CONFIG_LAST_CERT_ID=$(FN_ReadConfig "LAST_CERT_ID") || return 0
    [ -z "$CONFIG_LAST_CERT_ID" ] && CONFIG_LAST_CERT_ID=0
    CURRENT_CERT_ID=$((CONFIG_LAST_CERT_ID + 1))

    CURRENT_CERT_DIR="$PATH_CERTS_DIR/${CURRENT_CERT_ID}|${MAN_CN}"
    mkdir -p "$CURRENT_CERT_DIR"
    if [ $? -ne 0 ]; then
        FN_ShowError "Gagal Membuat Direktori" "Tidak dapat membuat direktori: $CURRENT_CERT_DIR"
        return 1
    fi

    CREATE_CERT_RESULT=$(openssl req -x509 -nodes -days "3650" -newkey rsa:4096 \
        -keyout "$CURRENT_CERT_DIR/privkey.pem" \
        -out "$CURRENT_CERT_DIR/fullchain.pem" \
        -subj "/C=$MAN_COUNTRY/CN=$MAN_CN/emailAddress=$MAN_EMAIL/O=${OPS_ORG:-$MAN_CN}")
    if [ $? -ne 0 ]; then
        FN_ShowError "Gagal Membuat Sertifikat" "Tidak dapat membuat sertifikat: $CREATE_CERT_RESULT"
        return 1
    fi

    FN_WriteConfig "LAST_CERT_ID" "$CURRENT_CERT_ID" || return 1
    FN_ShowInfo "Sertifikat Berhasil Dibuat" "Sertifikat dengan common name '$MAN_CN' telah berhasil dibuat!" && return 0
}

FN_GetAvailableCertificates() {
    
    DATA_CERTIFICATES_AVAILABLE=()
    
    for COMMON_NAME_DIR in "$PATH_CERTS_DIR"/*; do
    
        # Jika item dalam $PATH_CERTS_DIR bukan direktori, skip.
        [ ! -d "$COMMON_NAME_DIR" ] && continue
        
        local FULLCHAIN_CERT_PATH="$COMMON_NAME_DIR/fullchain.pem"
        local KEY_CERT_PATH="$COMMON_NAME_DIR/privkey.pem"

        # Jika file sertifikat lengkap dan kunci privat ada, tambahkan ke daftar pilihan.
        if [[ -f "$FULLCHAIN_CERT_PATH" && -f "$KEY_CERT_PATH" ]]; then
            # Ambil nama sertifikat dari nama direktori paling kanan dalam path.
            local BASENAME=$(basename "$COMMON_NAME_DIR") || return 1

            # Ambil ID dan nama sertifikat dengan Internal Field Separator (IFS) untuk memisahkan berdasarkan delimiter '|'.
            local CERT_ID CERT_NAME
            IFS="|" read -r CERT_ID CERT_NAME <<< "$BASENAME"

            # Tambahkan ke tuple sebagai pilihan sertifikat yang valid.
            DATA_CERTIFICATES_AVAILABLE+=("FALSE" "$CERT_ID" "$CERT_NAME")
            
            # Simpan path sertifikat ke dalam map (array) untuk akses cepat.
            DATA_MAP_CERTIFICATES_AVAILABLE["$CERT_ID"]="$FULLCHAIN_CERT_PATH;$KEY_CERT_PATH"
        fi
    done
    
    return 0
}

FN_ShowSelectAvailableCertificates() {
    zenity --list --radiolist --title="Pilih Sertifikat" --text="Pilih sertifikat elektronik yang ingin digunakan untuk menandatangani dokumen." --column="#" --column="ID Sertifikat" --column="Nama Sertifikat" --print-column=2 --width=${UI_WINDOW_SIZE_GENERAL[0]} --height=${UI_WINDOW_SIZE_GENERAL[1]} "${DATA_CERTIFICATES_AVAILABLE[@]}"
}

FN_SignPDF() {
    local PDF_FILE="$1"
    local CERT_FILE="$2"
    local KEY_FILE="$3"
    local OUTPUT_FILE_PATH="$4"
    local RESULT

    echo "Menandatangani $PDF_FILE ..."
    RESULT=$(java -jar "$PATH_SIGNER" -c "$CERT_FILE" -k "$KEY_FILE"  -i "$PDF_FILE"  -o "$OUTPUT_FILE_PATH" )
    
    if [ $? -eq 0 ]; then
        echo "Penandatanganan OK!"
        FN_ShowInfo "Berhasil" "File PDF berhasil ditandatangani dan telah disimpan di:\n$OUTPUT_FILE_PATH\n\n$(pdfsig "$OUTPUT_FILE_PATH")"
        return 0
    else
        echo "Penandatanganan GAGAL! $RESULT"
        FN_ShowError "" "File PDF gagal ditandatangani.\n\n$RESULT"
        return 1
    fi
}
# =========================== END OF FUNCTIONS DEFINITION ===========================
# =========================== BEGINING OF ALGORITHM ===========================
LICENSE="$(FN_ReadConfig "LICENSE_AGREED")"

if [[ -z "$LICENSE" || ! "$LICENSE" = "TRUE" ]]; then
    FN_PromptLicense || exit 1
fi

FN_Init || exit 1

FN_GetAvailableCertificates || exit 1

if [ "${#DATA_CERTIFICATES_AVAILABLE[@]}" -eq 0 ]; then
    FN_CreateCertificate || exit 1
else
    SIGNATORY_CERT_OPTION=$(FN_SelectExistingOrCreateNewCert) || exit 1
    
    if [ "$SIGNATORY_CERT_OPTION" = "2" ]; then 
        FN_CreateCertificate || exit 1
    fi
fi

SELECTED_PDF_FILE=$(FN_SelectPDFFile) || exit 1

[ -z "$SELECTED_PDF_FILE" ] && exit 1;

while ! FN_CheckFileType "$SELECTED_PDF_FILE" "application/pdf"; do
    FN_ShowQuestion "File PDF Tidak Valid" "File yang dipilih\n$SELECTED_PDF_FILE\nbukan file PDF yang valid!\n\nIngin memilih file lain?" || exit 1
    SELECTED_PDF_FILE=$(FN_SelectPDFFile) || exit 1
done

FN_GetAvailableCertificates && SELECTED_SIGNATORY_CERTIFICATE_ID=$(FN_ShowSelectAvailableCertificates) || exit 1

IFS=";" read -r CERT_FILE KEY_FILE <<< "${DATA_MAP_CERTIFICATES_AVAILABLE["$SELECTED_SIGNATORY_CERTIFICATE_ID"]}"

OUTPUT_FILE_PATH=$(FN_StorePDFFilePath "$SELECTED_PDF_FILE") || exit 1

[ -z "$OUTPUT_FILE_PATH" ] && exit 1

FN_SignPDF "$SELECTED_PDF_FILE" "$CERT_FILE" "$KEY_FILE" "$OUTPUT_FILE_PATH" || exit 1
# =========================== END OF ALGORITHM ===========================