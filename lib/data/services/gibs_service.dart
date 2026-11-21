/// NASA GIBS — citra satelit MODIS Terra true color (tanpa key).
/// URL builder murni (tanpa jaringan): tanggal = KEMARIN (UTC),
/// karena citra hari ini bisa belum tersedia. Zoom maks 9.
class GibsService {
  GibsService();

  /// Template tile untuk tanggal tertentu (default: kemarin UTC).
  static String tileTemplate({DateTime? dateUtc}) {
    final date = (dateUtc ?? DateTime.now().toUtc())
        .subtract(const Duration(days: 1));
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return 'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/'
        'MODIS_Terra_CorrectedReflectance_TrueColor/default/$y-$m-$d/'
        'GoogleMapsCompatible_Level9/{z}/{y}/{x}.jpg';
  }
}
