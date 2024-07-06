# ninox.d-dsp

Package to provide a build-time template language called "DSP" (Dlang Server Pages).

## License

The code in this repository is licensed under AGPL-3.0-or-later; for more details see the `LICENSE` file in the repository.

## Usage

### Template syntax

The template syntax is heavily inspired by other "server pages" template systems.

There are special "tags" that start with `<%` and end with `%>`. The start tag is followed by a identifier, which is a string starting from the start-tag until the first space (or the endtag in some special cases). 

This identifier is used to determine what a tag is doing:

- `<%layout abc %>` specifies a layout (in this case `abc.dsp`), which is tried to be called with the current template as a delegate passed to `emitSlot` (see below).

- `<%head ... %>` contains arbitary dlang code to be emitted at the top-most level (or module level) of the generated dlang source file.

- `<%d ... %>` contains arbitrary dlang code to be emitted at the current position in the generated source file. This is usefull to make dynamic templates.

- `<%inc abc %>` includes a other template to be rendered at the current position. Here it tries to include `abc.dsp`. You can specify which data to render the template with, by writing a dlang expression right after the template name: `<%inc abc 12 %>`.

- `<%slot %>` is the "slot" or insertion-point for a template that is rendered as a layout for another template.

- `<%attrs ... %>`'s content will be emitted as the template's rendering funcion's attributes. With this it is possible to add `@gc` or similar attributes to the rendering function. Example: `<%attrs @gc %>`.

Additionally there exists two syntaxes for directly rendering data; note that each result is first passed to `std.conv.to!(const char[])` before emitted:

- `{% expr %}` uses the given content and treats it as a dlang expression, which result needs to be emitted.

- `[[ name ]]` can be used in combination with a assocative array as data to lookup the given name inside it. Technically, this is compiled down to `ctx.data["name"]`, this also allowing any custom type that implements the index operator with a string parameter to be used.

Abart from that, the dlang code specified in the various tags can always refer to `ctx` for the given render context (see below). The `<%d` tags also is allowed to use `@` to refer to `ctx.data` and `$(...)` for a call to `ctx.emit(...)`.

### Whitespace triming

Each tag (i.e. `<%d ... %>`), is allowed to have one special "whitespace-control" character as it's first or last character in its identifier; is is removed upon detection and does not alter the general meaning of the tag in any other way expect the effects described here:

- `<%-xxx` strips any previous text content's right whitespace until a newline. I.e.:
    ```dsp
    <div>
        <d+ %>a
    </div>
    ```
    Will remove the four spaces before the `<%d`, resulting in:
    ```dsp
    <div>
    a
    </div>
    ```

- `<%xxx-` strips any whitespace after the tag up and including a newline:
    ```dsp
    <div>
        <%d %>
    a
    </div>
    ```
    Will remove the newline after the `%>`, resulting in:
    ```dsp
    <div>
        a
    </div>
    ```

- `<%xxx!` or `<%!xxx` combines the effects of the previous two.

### Rendering templates

Each generated sourcefile will have an exported `renderTemplate` function you can use to render the template. It's signature is as follows:
```d
import ninox.dsp : Context;
public void renderTemplate(ref Context ctx, void delegate() emitSlot = null);
```

The first parameter, `ref Context ctx` is the rendering context. It holds:
- the `emit` callable which accepts a `const char[]` as single parameter and has a returntype of `void`. It is used by the templates to emit text data.
- the `data` variant, which can hold *any* data.

The second parameter, `void delegate() emitSlot` is a optional delegate to render the `<%slot%>` element. Will be un-used if no slot is present.

### Processing template files

To process template files, you'll need to run this package via `dub run`:

```sh
$ dub run ninox-d_dsp -- --input=./templates --output=./source --package=app
```

The command above will read templates from the `./templates` path by building and executing the glob `./templates/**/*.dsp`. The generated code will be written into `./source`, where each `.dsp` file will get transformed into a `.gen.d` file. Folder structure is preserved. It uses the package name (or module prefix to be precise) of `app`. Each generated dlang sourcefile will also contain the folder path relative to the input path in its module name.

For example, a template located at `./templates/some/path/file.dsp` will be written to `./source/some/path/file.dsp.gen.d`, with a module identifier of `app.some.path.file`.

### Usage in projects via dub

To start using dsp files, you'll need to do the following:

- edit your project's `dub.json`
    - add a dependency for `ninox-d_dsp`
    - add `dub run ninox-d_dsp -- --input=xxx --output=xxx --package=xxx` to `preGenerateCommands`, and replace / set the options accordingly.

- use the `renderTemplate` function(s) of the modules generated
