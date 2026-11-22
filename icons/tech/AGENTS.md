Technology Icon Guidelines

Itinera Urbis — Visual Asset Creation Standard

1. General Concept

All technology icons in Itinera Urbis must share a consistent visual style and identical base composition.

Every icon is built around a single, standardized graphical template: a blue circular background with a golden rim and a black outline.

The template is an immutable element. The artist or AI agent's task is to create the central illustration representing a specific technology, not to redraw the entire icon.

2. Base Template

The following file must be used when creating technology icons:

"icons/tech/template.png"

The template contains:

- A circular blue background with a gradient.
- A three-dimensional golden rim.
- A thick black outer outline.
- A black inner outline separating the rim from the blue background.
- Directional lighting from the upper-left.
- Characteristic highlights on both the golden rim and the blue surface.

The following modifications are strictly prohibited:

- Redrawing or recreating the template.
- Changing its color palette.
- Changing the thickness of the rim or outlines.
- Changing the lighting direction.
- Adding custom highlights or decorative elements to the frame.
- Using alternative shades of gold or blue.

The original template must be used directly, without generative reconstruction.

3. Central Illustration

The central illustration must clearly represent the corresponding technology.

General requirements:

- One large central object, or a small group of closely related objects when required by the technology's concept.
- The illustration must remain recognizable at small sizes.
- Prefer simple, expressive silhouettes.
- Keep small details to a minimum.
- Do not add decorative objects unrelated to the technology.

Historically accurate objects, tools, mechanisms, and equipment appropriate to the relevant era are encouraged.

Avoid photorealism and excessive detail.

4. Art Style

The central illustration must follow these visual characteristics:

- Stylized digital illustration.
- Three-dimensional cartoon-like appearance.
- Rich, clean, saturated colors.
- Thick, consistent black outlines.
- Clearly defined highlights and shadows to convey volume.
- Smooth color transitions within individual elements.
- Lighting from the upper-left.
- Strong silhouette readability.

The illustration must look like part of a unified game icon collection, not an independent illustration in a different art style.

5. Composition

The central object must be positioned in the middle of the blue area of the template.

Placement requirements:

- The object must be large enough to remain clearly recognizable.
- Visual centering must be maintained.
- The object must not overlap the golden rim.
- A small visual margin must remain between the object and the inner edge of the frame.
- Avoid excessively small objects surrounded by large amounts of empty space.

The perspective and viewing angle should be chosen according to the object being depicted, while maintaining the overall three-dimensional visual style of the icon collection.

6. Transparency and File Format

The final icon must:

- Have a transparent background outside the circular frame.
- Preserve all elements of the original template.
- Contain a proper alpha channel.
- Be saved in PNG format.
- Retain the original template's resolution and aspect ratio.

A checkerboard pattern simulating transparency, or a white or black background instead of actual transparency, is not acceptable.

7. Recommended Creation Workflow

Icon creation should be performed in two stages.

Stage 1. Generate the Central Illustration

The AI agent generates only the central object on a transparent background.

The generation prompt must include:

- A description of the specific technology.
- The original template as a visual reference for the art style.
- Requirements concerning detail level, colors, outlines, and lighting.

The golden frame and blue circular background must NOT be generated again.

Stage 2. Composition

The central illustration is placed on top of the original template.

Automated composition using a predefined placement area for the central illustration is recommended.

8. Quality Control

Before adding an icon to the game, verify the following:

1. Was the original template used without modifications?
2. Are the original colors and gradients preserved?
3. Is the original lighting direction preserved?
4. Are the rim and outline thicknesses unchanged?
5. Is the central object sufficiently large?
6. Is it clearly recognizable at reduced sizes?
7. Does the illustration match the overall art style?
8. Is the background genuinely transparent?

If any requirement concerning the template is violated, the icon must be reassembled.

---

9. The Most Important Rule

All technology icons in Itinera Urbis must look as if they were created by the same artist as part of a single, unified graphical collection.

The individuality of each icon must come from the technology it depicts, not from variations in the frame, background, or lighting.
