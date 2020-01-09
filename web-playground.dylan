Module: web-playground
Synopsis: Web app backing play.opendylan.org

/*
TODO

* Provide a separate <textarea> for the library / module definitions, with a
  widget to minimize it.

* Permalinks for sharing examples.

* The TODOs in the code below are the more urgent ones. These are longer term
  reminders.

* Provide a bunch of code examples to select from and then modify.

* Provide a way to create your own library and module definition rather than
  using the canned ones. Probably just search for "define library" and "define
  module" and omit the canned ones if present. Need to ensure they don't
  redefine any of the core libraries.

* Re-evaluate the list of imported modules in the canned module definition.
  Not sure how Bruce came up with that list but it looks like a good start.

* For now I compile all code in the same _build directory. Is this safe if
  multiple compilations are running at the same time? At least I think the file
  sets are disjoint as long as none of the used libraries need to be
  recompiled.  Could instead copy a _build dir that has core libs precompiled.

* Optionally show DFM and/or assembly output.

*/

// Make #:string:|...| syntax work.
define function string-parser (s) => (s) s end;

define class <playground-page> (<dylan-server-page>)
end;

define constant $playground-page = make(<playground-page>, source: "playground.dsp");

define constant $default-code = #:string:|
// Edit this code, then hit Run.

define function main ()
  format-out("Hello, %s!\n", "World");
end;

main();
|;

define constant $warnings-attr = "warnings";
define constant $exe-output-attr = "exe-output";
define constant $debug-output-attr = "debug-output";

define taglib playground ()
  tag dylan-code (page :: <playground-page>) ()
    output("%s", get-query-value("dylan-code") | $default-code);
  tag warnings (page :: <playground-page>) ()
    quote-html(get-attribute(page-context(), $warnings-attr) | "",
               stream: current-response());
  tag exe-output (page :: <playground-page>) ()
    quote-html(get-attribute(page-context(), $exe-output-attr) | "",
               stream: current-response());
  tag debug-output (page :: <playground-page>) ()
    quote-html(get-attribute(page-context(), $debug-output-attr) | "",
               stream: current-response());
end;

define method respond-to-post (page :: <playground-page>, #key) => ()
  // Seems like text/html should be the default...
  set-header(current-response(), "Content-Type", "text/html");
  let dylan-code = get-query-value("dylan-code");
  if (dylan-code & dylan-code ~= "")
    block ()
      let project-name = generate-project-name();
      let (warnings, exe-output) = build-and-run-code(project-name, dylan-code);
      set-attribute(page-context(), $warnings-attr, warnings);
      set-attribute(page-context(), $exe-output-attr, exe-output);
    exception (ex :: <error>)
      format-to-string("Error: %s", ex)
    end;
  else
    "Please enter some code above."
  end;
  process-template(page);
end;

define function generate-project-name () => (project-name :: <string>)
  // Good enough for now...
  current-request().request-client-address.md5.hexdigest
end function;

define function build-and-run-code
    (project-name :: <string>, dylan-code :: <string>)
 => (warnings :: <string>, exe-output :: <string>)
  let workdir = ensure-working-directory(project-name);
  let lid-path = generate-project-files(project-name, workdir, dylan-code);
  let (exe-path, warnings) = build-project(project-name, workdir, lid-path);
  if (exe-path)
    values(warnings, run-executable(workdir, exe-path))
  else
    values(warnings, "No executable was created")
  end
end function;

define function run-executable
    (workdir :: <directory-locator>, exe-path :: <file-locator>) => (output :: <string>)
  let exe-output
    = with-output-to-string (stream)
        os/run-application(as(<string>, exe-path),
                           working-directory: workdir,
                           input: #"null",
                           outputter: method (output :: <byte-string>, #key end: _end :: <integer>)
                                        log-debug("program output: %s", copy-sequence(output, end: _end));
                                        write(stream, output, end: _end);
                                      end);
      end;
  exe-output | "(no output)"
end function;

define function ensure-working-directory
    (project-name :: <string>) => (pathname :: <directory-locator>)
  let workdir = as(<directory-locator>, format-to-string("/tmp/%s", project-name));
  fs/ensure-directories-exist(workdir);
  workdir
end function;

define function generate-project-files
    (project-name :: <string>, workdir :: <directory-locator>, dylan-code :: <string>)
 => (lid :: <file-locator>)
  let (lid-path, lib-path, code-path)
    = apply(values, project-locators(project-name, workdir));
  fs/with-open-file (stream = lib-path, direction: #"output", if-exists: #"truncate")
    format(stream, $library-file-template, project-name, project-name);
  end;
  fs/with-open-file (stream = code-path,  direction: #"output", if-exists: #"truncate")
    format(stream, $code-file-template, project-name, dylan-code);
  end;
  fs/with-open-file (stream = lid-path,  direction: #"output", if-exists: #"truncate")
    format(stream, $lid-file-template, project-name, project-name, project-name, project-name);
  end;
  lid-path
end function;

define function project-locators
    (project-name :: <string>, workdir :: <directory-locator>) => (locators :: <sequence>)
  map(method (fmt)
        merge-locators(as(<file-locator>,
                          format-to-string(fmt, project-name)),
                       workdir)
      end,
      #("%s.lid", "%s-library.dylan", "%s-code.dylan"))
end function;

define constant $lid-file-template
  = "library: %s\nexecutable: %s\nfiles: %s-library\n       %s-code\n";

define constant $library-file-template = #:string:|module: dylan-user

// If a library has no import: clause here it imports a module with the same
// name as the library.
define library %s
  use collections, import: { bit-set, bit-vector, byte-vector, collectors, set, table-extensions };
  use common-dylan, import: { common-dylan, machine-words, simple-random, transcendentals };
  use hash-algorithms;
  use io, import: { format, format-out, print, standard-io, streams };
  use json;
  use regular-expressions;
  use strings;
  use system, import: { date };
end library;

define module %s
  use bit-set;
  use bit-vector;
  use byte-vector;
  use collectors;
  use common-dylan;
  use date;
  use format-out;
  use format;
  use machine-words;
  use print;
  use set;
  use simple-random;
  use standard-io;
  use streams;
  use table-extensions;
  use transcendentals;
end module;
|;

define constant $code-file-template = "module: %s\n\n%s\n";

define function build-project
    (project-name :: <string>, workdir :: <directory-locator>, lid-path :: <file-locator>)
 => (exe :: false-or(<file-locator>), warnings :: <string>)
  let command = format-to-string("dylan-compiler -build %s", lid-path);
  let builder-output
    = with-output-to-string (stream)
        os/run-application(command,
                           working-directory: workdir,
                           input: #"null",
                           outputter: method (output :: <byte-string>, #key end: _end :: <integer>)
                                        log-debug("compiler output: %s", copy-sequence(output, end: _end));
                                        write(stream, output, end: _end);
                                      end);
      end;
  let exe-path = merge-locators(as(<file-locator>,
                                   format-to-string("_build/bin/%s", project-name)),
                                workdir);
  let warnings = sanitize-build-output(builder-output);
  if (fs/file-exists?(exe-path))
    values(exe-path, warnings)
  else
    values(#f, warnings)
  end
end function;

// Don't show compiler output lines with these prefixes.  Seemed safer than a
// whitelist.
define constant $blacklist-prefixes
  = #["Opened project",
      "Loading namespace",
      "Updating definitions",
      "Computing data models",
      "Computing code models",
      "Performing type analysis",
      "Optimizing",
      "Generating code",
      "Linking object files",
      "Saving database",
      "Checking bindings",
      "Linking"];

define function sanitize-build-output (output :: <string>) => (sanitized :: <string>)
  local method keep-line? (line)
          // Wouldn't mind having an option to dylan-compiler to turn off most
          // of the output other than "building library foo" and warnings.
          ~any?(starts-with?(line, _), $blacklist-prefixes)
        end;
  let lines = choose(keep-line?, split(output, "\n"));
  // Remove all warnings from the dylan library.
  // (Not technically necessary given the plan to install precompiled core libs.)
  let trimmed = make(<stretchy-vector>);
  let keep? = #t;
  for (line in lines)
    if (starts-with?(line, "/"))
      keep? := ~find-substring(line, "/sources/dylan/");
    end;
    if (keep?)
      add!(trimmed, line);
    end;
  end;
  join(trimmed, "\n")
end function;

define function main ()
  let server = make(<http-server>);
  add-resource(server, "/play", $playground-page);
  http-server-main(server: server);
end function;

main();
