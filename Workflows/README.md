# Face Puppet textures

These files help you create a puppet texture that maps cleanly onto the live
MediaPipe face mesh in FreeStage.

## How the mapping works

FreeStage’s Face Puppet renderer uses MediaPipe’s canonical 468-point face mesh.
Each vertex has a fixed UV coordinate. The renderer deforms that mesh to match
your face, then samples the puppet image at those UVs.

Think of it like a texture atlas: the puppet image is stretched so that its
eyes, nose and mouth land on your real eyes, nose and mouth.

## What makes a good puppet image

- **Front-facing and symmetrical.** The mesh is built for a face looking
  straight at the camera. Profile or 3/4 images will not align.
- **Neutral expression.** The canonical mesh is roughly neutral. Big smiles,
  open mouths or closed eyes map to the wrong parts of your face.
- **Centered and fills the frame.** The face should sit in the middle of the
  image, not cropped to one side.
- **Transparent or soft edges.** Only the face area is wrapped; any hard
  background rectangle will be glued to your cheeks. Use a PNG with an alpha
  channel, or paint the neck/cheeks so they blend into your skin.
- **Square-ish canvas.** The usable UV region is slightly wider than tall
  (about 1.16:1), but a 1:1 square image works fine. Recommended sizes:
  1024×1024 or 512×512.

## Provided files

- `puppet_uv_template.png` — wireframe overlay of the canonical face mesh.
  Open this in Photoshop / GIMP / Affinity / Photopea and paint your puppet
  face underneath it.
- `puppet_texture_example.png` — a quick ComfyUI-generated example. It is not
  perfect, but it shows the kind of front-facing stylised face that works.
- `puppet_skin_texture.json` — ComfyUI workflow used to generate the example.

## Quick recipe in an image editor

1. Create a new 1024×1024 canvas.
2. Place `puppet_uv_template.png` on the top layer and set it to 30–50 % opacity.
3. On layers underneath, paint or paste a front-facing face so that:
   - the eyes sit under the eye markers,
   - the nose tip sits under the nose marker,
   - the mouth sits under the mouth marker,
   - the chin sits near the bottom marker.
4. Hide or delete the template layer.
5. Export as PNG with transparency and load it into FreeStage.

## Quick recipe with ComfyUI

Make sure ComfyUI is running locally, then:

```bash
"<home>/GitHub/Creative Tools/ComfyUI/.venv/bin/python" \
  scripts/generate_puppet_texture.py \
  --output ~/Desktop/my_puppet.png \
  --prompt "front-facing stylized puppet face texture, symmetrical neutral expression, large clear eyes, nose and mouth centered, looking directly at camera, flat lighting, isolated on transparent background, anime style"
```

Edit `Workflows/puppet_skin_texture.json` to change the checkpoint or sampler
settings. The default checkpoint is `CounterfeitXL-V1.0.safetensors`, which
produces an anime/cartoon look; swap it for any checkpoint in your ComfyUI
`checkpoints` folder.

## What to avoid

- Full-body or portrait photos with lots of hair/background.
- Side-profile or tilted faces.
- Heavy shadows or perspective.
- Text, watermarks or logos — they will be warped across the face.
