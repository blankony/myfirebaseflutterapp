// Data for PNJ Departments and Study Programs
class PnjData {
  static const Map<String, List<Map<String, String>>> departments = {
    'Teknik Sipil': [
      {'name': 'Konstruksi Gedung (D3)', 'code': 'TS-KG'},
      {'name': 'Konstruksi Sipil (D3)', 'code': 'TS-KS'},
      {'name': 'Teknik Perancangan Jalan & Jembatan (D4)', 'code': 'TS-PJ'},
      {'name': 'Teknik Konstruksi Gedung (D4)', 'code': 'TS-KGG'},
    ],
    'Teknik Mesin': [
      {'name': 'Teknik Mesin (D3)', 'code': 'TM-TM'},
      {'name': 'Teknologi Rekayasa Konversi Energi (D4)', 'code': 'TM-KR'},
      {'name': 'Teknologi Rekayasa Pemeliharaan Alat Berat (D4)', 'code': 'TM-AB'},
      {'name': 'Manufaktur (D4)', 'code': 'TM-MF'},
      {'name': 'Pembangkit Tenaga Listrik (D4)', 'code': 'TM-PL'},
    ],
    'Teknik Elektro': [
      {'name': 'Elektronika Industri (D3)', 'code': 'TE-EI'},
      {'name': 'Teknik Listrik (D3)', 'code': 'TE-TL'},
      {'name': 'Telekomunikasi (D3)', 'code': 'TE-TEL'},
      {'name': 'Instrumentasi & Kontrol Industri (D4)', 'code': 'TE-IK'},
      {'name': 'Broadband Multimedia (D4)', 'code': 'TE-BM'},
      {'name': 'Teknik Otomasi Listrik Industri (D4)', 'code': 'TE-OLI'},
    ],
    'Teknik Informatika & Komputer': [
      {'name': 'Teknik Informatika (D4)', 'code': 'TI-TI'},
      {'name': 'Teknik Multimedia & Jaringan (D4)', 'code': 'TI-MJ'},
      {'name': 'Teknik Multimedia Digital (D4)', 'code': 'TI-MD'},
      {'name': 'Teknik Komputer & Jaringan (D1)', 'code': 'TI-KJ'},
    ],
    'Akuntansi': [
      {'name': 'Akuntansi (D3)', 'code': 'A-AK'},
      {'name': 'Keuangan & Perbankan (D3)', 'code': 'A-KP'},
      {'name': 'Keuangan & Perbankan Syariah (D4)', 'code': 'A-KPS'},
      {'name': 'Akuntansi Keuangan (D4)', 'code': 'A-AKK'},
      {'name': 'Manajemen Keuangan (D4)', 'code': 'A-MK'},
    ],
    'Administrasi Niaga': [
      {'name': 'Administrasi Bisnis (D3)', 'code': 'AN-AB'},
      {'name': 'Usaha Jasa Konvensi, Perjalanan & Pameran / MICE (D4)', 'code': 'AN-MICE'},
      {'name': 'Administrasi Bisnis Terapan (D4)', 'code': 'AN-ABT'},
      {'name': 'Bahasa Inggris untuk Komunikasi Bisnis & Profesional (D4)', 'code': 'AN-BEKP'},
    ],
    'Teknik Grafika & Penerbitan': [
      {'name': 'Teknik Grafika (D3)', 'code': 'TGP-TG'},
      {'name': 'Penerbitan (D3)', 'code': 'TGP-PN'},
      {'name': 'Desain Grafis (D4)', 'code': 'TGP-DG'},
      {'name': 'Teknologi Industri Cetak & Kemasan (D4)', 'code': 'TGP-TIC'},
    ],
  };
}