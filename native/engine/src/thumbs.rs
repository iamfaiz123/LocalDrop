//! Thumbnails. The original file is only ever read; thumbnails are separate
//! small JPEGs so the gallery never loads full-resolution media.

use image::{imageops::FilterType, DynamicImage, ImageDecoder, ImageReader, Limits};
use std::io::Cursor;
use std::path::Path;

pub const THUMB_MAX: u32 = 480;

fn limits(max_dim: u32, max_alloc: u64) -> Limits {
    let mut l = Limits::default();
    l.max_image_width = Some(max_dim);
    l.max_image_height = Some(max_dim);
    l.max_alloc = Some(max_alloc);
    l
}

fn encode_jpeg(img: &DynamicImage, dst: &Path) -> Result<(), String> {
    let thumb = img.resize(THUMB_MAX, THUMB_MAX, FilterType::Triangle).to_rgb8();
    let tmp = dst.with_extension("jpg.tmp");
    {
        let f = std::fs::File::create(&tmp).map_err(|e| e.to_string())?;
        let mut w = std::io::BufWriter::new(f);
        let mut enc = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut w, 80);
        enc.encode_image(&thumb).map_err(|e| e.to_string())?;
    }
    std::fs::rename(&tmp, dst).map_err(|e| e.to_string())
}

/// Generates a thumbnail for a server-decodable photo. Honors EXIF orientation.
/// Returns the original dimensions (after orientation).
pub fn generate_from_file(src: &Path, dst: &Path) -> Result<(u32, u32), String> {
    let mut reader = ImageReader::open(src).map_err(|e| e.to_string())?.with_guessed_format().map_err(|e| e.to_string())?;
    reader.limits(limits(16_384, 768 * 1024 * 1024));
    let mut decoder = reader.into_decoder().map_err(|e| e.to_string())?;
    let orientation = decoder.orientation().ok();
    let mut img = DynamicImage::from_decoder(decoder).map_err(|e| e.to_string())?;
    if let Some(o) = orientation {
        img.apply_orientation(o);
    }
    encode_jpeg(&img, dst)?;
    Ok((img.width(), img.height()))
}

/// Validates and re-encodes a client-supplied thumbnail (for videos, HEIC…).
/// Re-encoding guarantees only a plain JPEG is ever served back.
pub fn store_client_thumbnail(bytes: &[u8], dst: &Path) -> Result<(), String> {
    let mut reader = ImageReader::new(Cursor::new(bytes)).with_guessed_format().map_err(|e| e.to_string())?;
    match reader.format() {
        Some(image::ImageFormat::Jpeg | image::ImageFormat::Png | image::ImageFormat::WebP) => {}
        _ => return Err("thumbnail must be JPEG, PNG or WebP".into()),
    }
    reader.limits(limits(2048, 64 * 1024 * 1024));
    let img = reader.decode().map_err(|e| e.to_string())?;
    encode_jpeg(&img, dst)
}

/// Reads only the image header to get dimensions (cheap).
pub fn dimensions(src: &Path) -> Option<(u32, u32)> {
    ImageReader::open(src).ok()?.with_guessed_format().ok()?.into_dimensions().ok()
}
