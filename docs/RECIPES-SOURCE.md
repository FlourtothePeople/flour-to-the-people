# The five recipes were copied from the earlier edit.site blog through its public API

The recipes are static text inside `public/index.html` (class `recipe-card`). Nothing fetches them at run time. This file records where they came from, in case the earlier site is still reachable and a recipe needs re-checking.

- Blog ID: `55213` (found in the `data-settings` attribute of a recipe page on the earlier site).
- List endpoint: `https://rest.edit.site/page-render-service/blog/55213/post` (returned 5 posts).
- One recipe: `https://rest.edit.site/page-render-service/blog/55213/post/{slug}`.
- Slugs: `gluten-free-artisan-bread`, `olive-oil-pizza-flatbread-dough`, `whole-grain-peasant-bread`, `rosemary-focaccia`, `gingerbread-cookies`.
- The `content` field is HTML from the Slate editor: text sits in `span[data-slate-string]` elements inside `ul`, `ol`, `li`, and `h2`.
- The gluten-free bread recipe is credited to *Gluten-Free Artisan Bread in Five Minutes a Day* (https://artisanbreadinfive.com/buying-our-books/); keep that attribution and link.
- The earlier site's recipe photos returned HTTP 403 from its image host, so the recipe cards use the existing product photos.
