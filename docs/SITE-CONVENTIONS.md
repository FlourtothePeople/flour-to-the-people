# The site follows strict rules set by its original author, and three designs were tried and rejected

Follow these rules when changing `public/index.html`. Items marked "checked" are enforced by a script or were confirmed in the file.

## Structure

- The site has five tabs in the top bar: Home, Shop, Recipes, FAQs, Contact. Shop does not open its own page; it scrolls Home to the product filter row (`id="filt-anchor"`, function `scrollToFlours()`).
- Home, Shop, and Contact use the red and black scheme. Recipes and FAQs use the green and black scheme (the tab class `g`). The top bar border and the selected tab take the page's color.
- The filter buttons above the products are All, Bread Flours, Ancient Grains, Gluten-Free, Mixes, and Grain-Free Flours (checked). A product may belong to several categories through the space-separated `data-c` attribute (for example `ancient gf`).
- Recipe cards open on click and stay open (checked: the click handler tests `classList.contains('recipe-card')`).

## Type, size, and color

- **No font size below 12px, anywhere** (checked by `npm run check`). Inline `style=""` attributes override stylesheet rules, so earlier violations came from inline attributes. Address lines and hours in the location tables had `font-size:9px` inline until they were replaced by classes.
- The font variables `--fd`, `--fb`, and `--fc` start with `Space Mono`; body text falls back to Verdana (checked).
- The palette variables are `--k` #0A0A0A, `--r` #CC0000, `--g` #1A6B1A, `--w` #F0EDE6 (checked). Prices use amber #FFA000 with a soft glow (checked).
- Color animations use OKLCH with `@property` so the hue changes smoothly. The top bar tabs cycle over 59 seconds (checked). Every animation needs a `prefers-reduced-motion` fallback (the file has five such blocks), and no animation may flash: keep luminance constant while hue changes.
- The author prefers compact layouts: small padding and line height, one row instead of several where content fits.

## Wording

- Use "worker-owned and controlled" and "syndicate" (the earlier text said "cooperative"). The location subtitle is "Appalachia".
- Product descriptions and ingredient lists were corrected from the actual bag labels (commit `83b02cd`). Do not reword ingredients without the label in hand.
- **Never call grain or flour "organic" in ingredient lists or product text.** Since October 2026 every grain is either certified organic or grown in and around Floyd County by small farmers who never spray it (soil free of pesticide residue), and it varies by batch; all of it is non-GMO. Under USDA rules (7 CFR 205.310) grain from small exempt farms may not be represented as organic in a product someone else processes, so ingredient lists name the grain only, and the sourcing is explained once in the "Organic or Better" box and the FAQ. "Never sprayed" applies only to the local grain (certified organic allows approved sprays), so the tagline says "Non-GMO".

## Designs tried and rejected (do not propose them again)

1. **Glass-gem corn photo as a tiled page background with a heavy black stroke on all text.** Three implementations failed to render cleanly: stacked `text-shadow` layers produced ghost outlines, a duplicate-text pseudo-element with `z-index:-1` disappeared behind ancestor stacking contexts, and a global `text-shadow` on `body` inherited into selected tabs and hid their black-on-red text. It was removed completely.
2. **Muted earthy palette (umber, iron oxide, moss, oatmeal).** The author disliked it.
3. **Red and black diagonal flag behind the hero.** Replaced by an embroidered banner image, which was itself replaced in October 2026 (see 4).
4. **AI-generated embroidered banner** (watermill, mountains, fist with loaf, flour sack). Removed in October 2026 because it read as AI-made: warped lettering on the sack, uniform "stitching", every inch filled. A linocut millstone seal, a red-ring logo (too close to the Arm & Hammer mark) and gold-wheat recolorings were also tried. The hero now shows the mill's own hand-drawn logo, black on cream (`public/images/hero-logo.png`, made from the owner's 5000 px scan), centered over dark-red sunburst rays drawn in CSS (`.hero-logo-wrap::before`). `public/images/share.jpg` is the same composition at 1200×630 for link previews.

## Working method the author expects

- Changes should work on the first or second attempt. After repeated failures on one feature, revert cleanly to the last working state instead of stacking fixes.
- After any visual change, open the page in a browser or screenshot it and look at the result before reporting success.
- Keep images as files in `public/images/`, compressed as JPEG: the 18 product photos are 500 by 643 px, the hero banner is 1200 by 674 px, and all 19 files total about 970 KB (checked). The earlier single-file version embedded images as base64, which made that file several times larger.
