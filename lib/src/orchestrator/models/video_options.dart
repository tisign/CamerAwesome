enum CupertinoVideoCodec {
  /// The H.264 video codec.
  h264,

  /// The HEVC video codec.
  hevc,

  /// The HEVC video codec that supports an alpha channel.
  hevcWithAlpha,

  /// The JPEG video codec.
  jpeg,

  /// The Apple ProRes 4444 video codec.
  appleProRes4444,

  /// The Apple ProRes 422 video codec.
  appleProRes422,

  /// The Apple ProRes 422 HQ video codec.
  appleProRes422HQ,

  /// The Apple ProRes 422 LT video codec.
  appleProRes422LT,

  /// The Apple ProRes 422 Proxy video codec.
  appleProRes422Proxy,
}

enum CupertinoFileType {
  /// The UTI for the QuickTime movie file format.
  ///
  /// Files are identified with the .mov and .qt extensions.
  quickTimeMovie,

  /// The UTI for the MPEG-4 file format.
  ///
  /// Files are identified with the .mp4 extension.
  mpeg4,

  /// The UTI for the iTunes video file format.
  ///
  /// Files are identified with the .m4v extension.
  appleM4V,

  /// The UTI for the 3GPP file format.
  ///
  /// Files are identified with the .3gp, .3gpp, and .sdv extensions.
  type3GPP,

  /// The UTI for the 3GPP2 file format.
  ///
  /// Files are identified with the .3g2, .3gp2 extensions.
  type3GPP2,
}

enum CupertinoColorSpace {
  /// The standard RGB color space.
  ///
  /// This is the default color space.
  sRGB,

  /// The P3 D65 wide color space.
  p3_D65,

  /// The BT.2020 wide color space with HLG transfer function.
  ///
  /// This color space is used for HDR video.
  hlg_BT2020,

  /// The Apple Log Color space with BT2020 primaries.
  ///
  /// This color space is used for HDR video.
  appleLog,
}

class CupertinoVideoOptions {
  /// The video codec to use when recording a video.
  CupertinoVideoCodec codec;

  /// The file type to use when recording a video.
  ///
  /// **WARNING:** Be sure to use the correct file type extension for the video!
  CupertinoFileType fileType;

  /// The color space to use when recording a video.
  CupertinoColorSpace? colorSpace;

  int? fps;

  CupertinoVideoOptions({
    this.codec = CupertinoVideoCodec.h264,
    this.fileType = CupertinoFileType.quickTimeMovie,
    this.colorSpace,
    this.fps,
  });

  Map<String, dynamic> toMap() {
    return {
      'codec': codec.name,
      'fileType': fileType.name,
      'colorSpace': colorSpace?.name,
      'fps': fps,
    };
  }
}
