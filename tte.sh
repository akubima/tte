#!/bin/bash

# NOTE: 
# The character '|' and ';' are used as delimiter in this bash scripts and should not be used in any user input or inside any data except it become the delimiter itself.

PATH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH_CERTS_DIR="$PATH_SCRIPT_DIR/.certs"
PATH_SIGNER="$PATH_SCRIPT_DIR/.resources/open-pdf-sign.jar"
PATH_CONFIG_FILE="$PATH_SCRIPT_DIR/.resources/.config"
PATH_EULA_FILE="$PATH_SCRIPT_DIR/.resources/EULA.html"

CONFIG_KEY_EULA="EULA_AGREED"

UI_WINDOW_SIZE_GENERAL=(800 400)
UI_WINDOW_SIZE_ALERT=(300 100)

declare -A DATA_MAP_CERTIFICATES_AVAILABLE
DATA_CERTIFICATES_AVAILABLE=()
DATA_EULA_AGREED="FALSE"

mkdir -p "$PATH_CERTS_DIR"

# =========================== FUNCTIONS DEFINITION ===========================
FN_ReadConfig () {
    grep -q "^$CONFIG_KEY_EULA=TRUE$" "$PATH_CONFIG_FILE" 2> /dev/null && DATA_EULA_AGREED="TRUE" || DATA_EULA_AGREED="FALSE"
}

FN_WriteConfig () {
    local KEY="$1"
    local VALUE="$2"

    # Jika baris key=... sudah ada maka update nilainya saja.
    if grep -q "^$KEY=" "$PATH_CONFIG_FILE" 2> /dev/null; then
        sed -i "s|^$KEY=.*|$KEY=$VALUE|" "$PATH_CONFIG_FILE"
    else
        echo "$KEY=$VALUE" >> "$PATH_CONFIG_FILE"
    fi
}

FN_PromptEULA () {
    if [ ! -f "$PATH_EULA_FILE" ]; then
        FN_ShowError "" "EULA tidak dapat ditemukan!" 1
        return 1
    fi

    zenity --text-info --title="Perjanjian Lisensi Pengguna Akhir (EULA)" --filename="$PATH_EULA_FILE" --checkbox="Saya menyetujui ketentuan dalam EULA ini." --html --width=${UI_WINDOW_SIZE_GENERAL[0]} --height=${UI_WINDOW_SIZE_GENERAL[1]}

    if [ $? -eq 0 ]; then
        FN_WriteConfig "$CONFIG_KEY_EULA" "TRUE" && return 0
    fi

    return 1
}

FN_SelectExistingOrCreateNewCert () {
    zenity --list --radiolist --title="Tentukan Pilihan" --text="Gunakan sertifikat yang ada atau buat baru?" --column="#" --column="Nomor" --column="Pilihan" --print-column=2 --width=${UI_WINDOW_SIZE_GENERAL[0]} --height=${UI_WINDOW_SIZE_GENERAL[1]} "TRUE" 1 "Gunakan sertifikat yang ada" "FALSE" 2 "Buat sertifikat baru"
}

# Menampilkan dialog pemilihan file PDF.
FN_SelectPDFFile () {
    # Karena fungsi bash cuma bisa mengembalikan numeric integer value, maka langsung aja perintah tanpa dibungkus $(). 
    zenity --file-selection --title="Pilih File PDF Untuk Ditandatangani" --file-filter="*.pdf" --width=${UI_WINDOW_SIZE_GENERAL[0]} --height=${UI_WINDOW_SIZE_GENERAL[1]}
}

FN_StorePDFFilePath () {
    local PDF_FILE=$1

    zenity --file-selection --save --confirm-overwrite --title="Pilih Lokasi Penyimpanan Dokumen" --filename="${PDF_FILE%.pdf}-signed.pdf" --file-filter="*.pdf"
}

# Penmeriksa tipe file.
FN_CheckFileType () {
    local FILE="$1"
    local DESIRED_TYPE="$2"
    local FILE_TYPE=$(file --mime-type -b "$FILE")

    # IF statement dengan format [ condition ] && true || false
    [ "$FILE_TYPE" = "$DESIRED_TYPE" ] && return 0 || return 1
}

# Menampilkan close-ended question dialog.
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
    local THEN_EXIT="${3:-0}"

    zenity --error --title="$TITLE" --text="$MESSSAGE" --width=${UI_WINDOW_SIZE_ALERT[0]} --height=${UI_WINDOW_SIZE_ALERT[1]}

    [ "$THEN_EXIT" = 1 ] && exit 1
}

FN_ShowInfo () {
    local TITLE="${1:-"Informasi"}"
    local MESSSAGE="$2"

    zenity --info --title="$TITLE" --text="$MESSSAGE" --width=${UI_WINDOW_SIZE_ALERT[0]} --height=${UI_WINDOW_SIZE_ALERT[1]}
}

# Mendapatkan sertifikat yang tersedia dan valid di dalam direktori ./certs.
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
                local BASENAME=$(basename "$COMMON_NAME_DIR")

                # Ambil ID dan nama sertifikat dengan Internal Field Separator (IFS) untuk memisahkan berdasarkan delimiter '|'.
                local CERT_ID CERT_NAME
                IFS="|" read -r CERT_ID  CERT_NAME <<< "$BASENAME"

                # Tambahkan ke tuple sebagai pilihan sertifikat yang valid.
                DATA_CERTIFICATES_AVAILABLE+=("FALSE" "$CERT_ID" "$CERT_NAME")
                
                # Simpan path sertifikat ke dalam map (array) untuk akses cepat.
                DATA_MAP_CERTIFICATES_AVAILABLE["$CERT_ID"]="$FULLCHAIN_CERT_PATH;$KEY_CERT_PATH"
            fi
        done
    
    return 0
}

# Menampilkan daftar sertifikat yang tersedia dan user harus milih satu.
FN_ShowSelectAvailableCertificates() {
    zenity --list --radiolist --title="Pilih Sertifikat" --text="Pilih sertifikat elektronik yang ingin digunakan untuk menandatangani dokumen." --column="#" --column="ID Sertifikat" --column="Nama Sertifikat" --print-column=2 --width=${UI_WINDOW_SIZE_GENERAL[0]} --height=${UI_WINDOW_SIZE_GENERAL[1]} "${DATA_CERTIFICATES_AVAILABLE[@]}"
}

# Fungsi penandatanganan dokumen PDF.
FN_SignPDF() {
    local PDF_FILE="$1"
    local CERT_FILE="$2"
    local KEY_FILE="$3"
    local OUTPUT_FILE_PATH="$4"
    local RESULT

    RESULT=$(java -jar "$PATH_SIGNER" -c "$CERT_FILE" -k "$KEY_FILE"  -i "$PDF_FILE"  -o "$OUTPUT_FILE_PATH" )
    
    if [ $? -eq 0 ]; then
        FN_ShowInfo "Berhasil" "File PDF berhasil ditandatangani dan telah disimpan di:\n$OUTPUT_FILE_PATH\n\n$(pdfsig "$OUTPUT_FILE_PATH")"
        return 0
    else
        FN_ShowError "" "File PDF gagal ditandatangani.\n\n$RESULT"
        return 1
    fi
}
# =========================== END OF FUNCTIONS DEFINITION ===========================

# =========================== BEGINING OF ALGORITHM ===========================

FN_ReadConfig || exit 1

if [ "$DATA_EULA_AGREED" = "FALSE" ]; then
    FN_PromptEULA || exit 1
fi

FN_GetAvailableCertificates || exit 1

if [ "${#DATA_CERTIFICATES_AVAILABLE[@]}" -eq 0 ]; then
    FN_ShowInfo "" "Creating certificate..."
else
    SIGNATORY_CERT_OPTION=$(FN_SelectExistingOrCreateNewCert) || exit 1
    [ "$SIGNATORY_CERT_OPTION" = "2" ] && FN_ShowInfo "" "Creating certificate..."
fi

SELECTED_PDF_FILE=$(FN_SelectPDFFile) || exit 1

[ -z "$SELECTED_PDF_FILE" ] && exit 1;

# Jika file yang dipilih udu PDF atau ndak valid, tampilkan dialog konfirmasi buat minta pengguna untuk milih file lain atau membatalkan operasi.
while true; do
    FN_CheckFileType "$SELECTED_PDF_FILE" "application/pdf" && break
    FN_ShowQuestion "File PDF Tidak Valid" "File yang dipilih\n$SELECTED_PDF_FILE\nbukan file PDF yang valid!\n\nIngin memilih file lain?" && SELECTED_PDF_FILE=$(FN_SelectPDFFile) || exit 1
done

FN_GetAvailableCertificates && SELECTED_SIGNATORY_CERTIFICATE_ID=$(FN_ShowSelectAvailableCertificates) || exit 1

IFS=";" read -r CERT_FILE KEY_FILE <<< "${DATA_MAP_CERTIFICATES_AVAILABLE["$SELECTED_SIGNATORY_CERTIFICATE_ID"]}"

OUTPUT_FILE_PATH=$(FN_StorePDFFilePath "$SELECTED_PDF_FILE") || exit 1

[ -z "$OUTPUT_FILE_PATH" ] && exit 1

FN_SignPDF "$SELECTED_PDF_FILE" "$CERT_FILE" "$KEY_FILE" "$OUTPUT_FILE_PATH" || exit 1
# =========================== END OF ALGORITHM ===========================