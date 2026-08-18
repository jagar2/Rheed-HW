#!/usr/bin/env python3
"""
Generate test_image.mem for TestImageSource.vhd.

Output format: one 128-bit word per line, 32 hex digits, no prefix.
Pixel k of a word sits in bits [8k+7 : 8k] (LSB-first), matching the
sequentializer and crop addressing in CustomLogic.vhd.

Usage:
    python make_test_image.py                       # two gaussians (default)
    python make_test_image.py --preview             # also write a PNG to eyeball
    python make_test_image.py --from-png photo.png  # use a real image instead
"""

import argparse
import numpy as np

IMG_DIM = 320                       # frame is IMG_DIM x IMG_DIM, Mono8
PX_PER_WORD = 16                    # STREAM_DATA_WIDTH / BITS_PER_PIXEL
GRID_DIM = 40                       # FOLO output grid
NUM_DET = 5                         # detections per frame
CROP_DIM = 48                       # crop box fed to the gaussian core
CELL_SIZE = IMG_DIM // GRID_DIM     # 8

# ---------------------------------------------------------------------------
# Edit this list to change the test image. Each entry is one gaussian blob:
#   (centre_x, centre_y, sigma_x, sigma_y, peak_amplitude, rotation_deg)
# sigma_x is the horizontal width, sigma_y the vertical height; set them equal
# for a circular blob. rotation_deg tilts the ellipse (0 = axis-aligned).
# Coordinates are in pixels, origin top-left.
#
# Keep centres inside roughly px 40..290 on both axes, or the 48x48 crop box
# around the detection will run off the frame and get zero-padded (harmless,
# but it changes what the gaussian core sees). check_blobs() flags this.
# ---------------------------------------------------------------------------
BLOBS = [
    # cx   cy   sx    sy    amp  rot
    ( 72,  88,  4.0,  4.0,  255,  0),   # tight and bright
    (176,  64, 10.0,  4.5,  200,  0),   # wide, squat
    ( 96, 208,  4.5, 10.0,  230,  0),   # narrow, tall
    (232, 152,  7.0,  7.0,  160,  0),   # circular, dim
    (264, 256,  9.0,  5.0,  190, 30),   # tilted ellipse
]

BACKGROUND = 8          # flat DC floor, keeps the frame from being pure black
NOISE_SIGMA = 0.0       # set to e.g. 3.0 to add gaussian noise

# --- bounds used by --random ---------------------------------------------
RND_SIGMA = (3.5, 10.0)   # min/max sigma on each axis
RND_AMP = (120, 255)      # min/max peak amplitude
RND_ASPECT = 2.5          # max sigma_x/sigma_y ratio, either direction
MIN_SEP_PX = 40           # min centre-to-centre distance between blobs


def random_blobs(n=NUM_DET, rng=None, dim=IMG_DIM, crop_dim=CROP_DIM,
                 min_sep=MIN_SEP_PX, max_tries=20000):
    """
    Draw n gaussians with random positions, widths, heights and rotations,
    rejecting any that would break the pipeline geometry: every centre sits far
    enough inside the frame that its 48x48 crop box stays in bounds, every pair
    is at least min_sep apart (so they land in distinct grid cells and read as
    spatially separate peaks), and no blob is wider than the crop can hold.
    """
    rng = rng or np.random.default_rng()
    lo = crop_dim // 2 + 4                    # 28 : keeps crop origin >= 0
    hi = dim - crop_dim // 2 - 4              # 292
    smin, smax = RND_SIGMA
    smax = min(smax, crop_dim / 4.0)          # 2-sigma must fit the half-box

    blobs, tries = [], 0
    while len(blobs) < n:
        tries += 1
        if tries > max_tries:
            raise RuntimeError(
                f"could not place {n} blobs with min_sep={min_sep}px in "
                f"[{lo},{hi}]^2 - lower MIN_SEP_PX or reduce the count")
        cx = int(rng.integers(lo, hi + 1))
        cy = int(rng.integers(lo, hi + 1))
        if any((cx - bx) ** 2 + (cy - by) ** 2 < min_sep ** 2
               for bx, by, *_ in blobs):
            continue
        sx = float(rng.uniform(smin, smax))
        sy = float(rng.uniform(smin, smax))
        if max(sx / sy, sy / sx) > RND_ASPECT:
            continue                          # too elongated; redraw
        amp = int(rng.integers(RND_AMP[0], RND_AMP[1] + 1))
        rot = int(rng.integers(0, 180)) if abs(sx - sy) > 0.5 else 0
        blobs.append((cx, cy, round(sx, 1), round(sy, 1), amp, rot))
    return blobs


def render_gaussians(blobs, dim=IMG_DIM, background=BACKGROUND,
                     noise_sigma=NOISE_SIGMA, seed=0):
    y, x = np.mgrid[0:dim, 0:dim].astype(np.float64)
    img = np.full((dim, dim), float(background))
    for cx, cy, sx, sy, amp, rot in blobs:
        th = np.deg2rad(rot)
        dx, dy = x - cx, y - cy
        xr = dx * np.cos(th) + dy * np.sin(th)
        yr = -dx * np.sin(th) + dy * np.cos(th)
        img += amp * np.exp(-(xr ** 2 / (2.0 * sx ** 2) + yr ** 2 / (2.0 * sy ** 2)))
    if noise_sigma > 0:
        img += np.random.default_rng(seed).normal(0.0, noise_sigma, img.shape)
    return np.clip(img, 0, 255).astype(np.uint8)


def load_png(path, dim=IMG_DIM):
    from PIL import Image
    im = Image.open(path).convert("L").resize((dim, dim), Image.LANCZOS)
    return np.asarray(im, dtype=np.uint8)


def write_vhdl_pkg(img, path, px_per_word=PX_PER_WORD):
    """
    Emit the image as a VHDL package holding a constant array. Use this when
    Vivado will not synthesise the textio ROM initialisation - it removes all
    file I/O from the design, at the cost of a slower analyse.
    """
    flat = img.reshape(-1)
    nwords = flat.size // px_per_word
    width = px_per_word * 8
    name = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    with open(path, "w") as fh:
        fh.write("-- Generated by make_test_image.py - do not edit\n")
        fh.write("library ieee;\nuse ieee.std_logic_1164.all;\n\n")
        fh.write(f"package {name} is\n")
        fh.write(f"  constant TI_WORDS : natural := {nwords};\n")
        fh.write(f"  constant TI_WIDTH : natural := {width};\n")
        fh.write(f"  type ti_rom_t is array (0 to {nwords - 1}) of "
                 f"std_logic_vector({width - 1} downto 0);\n")
        fh.write("  constant TI_ROM : ti_rom_t := (\n")
        for i in range(nwords):
            word = 0
            for k, p in enumerate(flat[i * px_per_word:(i + 1) * px_per_word]):
                word |= int(p) << (8 * k)
            sep = "," if i < nwords - 1 else ""
            fh.write(f'    {i} => x"{word:0{px_per_word * 2}x}"{sep}\n')
        fh.write("  );\n")
        fh.write(f"end package {name};\n")
    return nwords


def write_mem(img, path, px_per_word=PX_PER_WORD):
    flat = img.reshape(-1)
    assert flat.size % px_per_word == 0, "frame size must be a whole number of words"
    with open(path, "w") as fh:
        for i in range(0, flat.size, px_per_word):
            word = 0
            for k, p in enumerate(flat[i:i + px_per_word]):
                word |= int(p) << (8 * k)          # pixel 0 -> LSB
            fh.write(f"{word:0{px_per_word * 2}x}\n")
    return flat.size // px_per_word


def check_blobs(blobs, num_det=NUM_DET, crop_dim=CROP_DIM, dim=IMG_DIM):
    """
    Report the 40x40 grid cell each blob centre falls in, and flag the two things
    that quietly break a test frame: two blobs sharing one cell (NMS can only
    ever return one detection there), and a crop box that runs off the frame.

    Crop geometry mirrors CustomLogic.vhd: box top-left = CELL_SIZE*cell
    + (CELL_SIZE/2 - crop_dim/2).
    """
    origin_offs = CELL_SIZE // 2 - crop_dim // 2        # -20 for 8 / 48
    rows, seen, warnings = [], {}, []

    for i, (cx, cy, sx, sy, amp, rot) in enumerate(blobs):
        gx, gy = int(cx) // CELL_SIZE, int(cy) // CELL_SIZE
        x0, y0 = CELL_SIZE * gx + origin_offs, CELL_SIZE * gy + origin_offs
        inb = (x0 >= 0 and y0 >= 0
               and x0 + crop_dim <= dim and y0 + crop_dim <= dim)
        rows.append((i, cx, cy, sx, sy, amp, rot, gx, gy, x0, y0, inb))

        if (gx, gy) in seen:
            warnings.append(f"blobs {seen[(gx, gy)]} and {i} share grid cell "
                            f"({gx},{gy}) - NMS can only report one of them")
        seen[(gx, gy)] = i

        if not inb:
            warnings.append(f"blob {i}: crop box ({x0},{y0})..({x0+crop_dim},"
                            f"{y0+crop_dim}) leaves the frame - will be zero-padded")
        if max(sx, sy) * 2 > crop_dim / 2:
            warnings.append(f"blob {i}: 2-sigma extent {max(sx, sy)*2:.0f}px "
                            f"exceeds the {crop_dim//2}px crop half-width - tails clipped")

    if len(blobs) > num_det:
        warnings.append(f"{len(blobs)} blobs but NUM_DET={num_det} - "
                        f"only the {num_det} strongest are cropped")
    return rows, warnings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default="test_image.mem")
    ap.add_argument("--from-png", default=None,
                    help="use this image instead of synthetic gaussians")
    ap.add_argument("--preview", action="store_true",
                    help="also write <out>.png so you can see what you built")
    ap.add_argument("--random", action="store_true",
                    help="draw random gaussians instead of the BLOBS list")
    ap.add_argument("--count", type=int, default=NUM_DET,
                    help=f"how many blobs when --random (default {NUM_DET})")
    ap.add_argument("--seed", type=int, default=None,
                    help="RNG seed for --random; omit for a fresh image each run")
    ap.add_argument("--vhdl", metavar="PKG.vhd", default=None,
                    help="also emit a VHDL package constant (no textio needed)")
    args = ap.parse_args()

    if args.from_png:
        img = load_png(args.from_png)
        print(f"source: {args.from_png}")
        blobs = None
    else:
        if args.random:
            # An explicit seed reproduces exactly; otherwise draw one and print
            # it, so any frame that trips a bug can be regenerated later.
            seed = args.seed if args.seed is not None else \
                int(np.random.SeedSequence().entropy % (2 ** 32))
            blobs = random_blobs(args.count, np.random.default_rng(seed))
            print(f"source: {len(blobs)} random gaussians  (--seed {seed})")
        else:
            blobs = BLOBS
            print(f"source: {len(blobs)} synthetic gaussians (BLOBS list)")
        img = render_gaussians(blobs)
        rows, warnings = check_blobs(blobs)
        print("   #   centre     sigma x/y   amp  rot     cell    crop origin")
        for (i, cx, cy, sx, sy, amp, rot, gx, gy, x0, y0, inb) in rows:
            print(f"   {i}  ({cx:3d},{cy:3d})  {sx:5.1f}/{sy:5.1f}  {amp:3d}  "
                  f"{rot:3d}   ({gx:2d},{gy:2d})   ({x0:3d},{y0:3d})"
                  f"{'' if inb else '  [OOB]'}")
        for w in warnings:
            print(f"   warning: {w}")

    n = write_mem(img, args.out)
    if args.vhdl:
        write_vhdl_pkg(img, args.vhdl)
        print(f"wrote {args.vhdl} (VHDL package, no file I/O at synthesis)")
    if blobs is not None:
        with open(args.out + ".blobs", "w") as fh:
            fh.write("# cx cy sigma_x sigma_y amp rot  ->  grid_cx grid_cy\n")
            for (i, cx, cy, sx, sy, amp, rot, gx, gy, *_) in rows:
                fh.write(f"{cx} {cy} {sx} {sy} {amp} {rot}  {gx} {gy}\n")
        print(f"wrote {args.out}.blobs (expected NMS cells)")
    print(f"wrote {args.out}: {n} words x {PX_PER_WORD} px, "
          f"min={img.min()} max={img.max()}")

    if args.preview:
        from PIL import Image
        Image.fromarray(img).save(args.out + ".png")
        print(f"wrote {args.out}.png")


if __name__ == "__main__":
    main()
