defmodule Mix.Tasks.Release.Clean do
  @moduledoc """
  Clean up any release-related files.

  ## Examples

      # Cleans the release for the current version of the project
      mix release.clean

      # Remove all files generated by exrm, including releases
      mix release.clean --implode

      # Implode, but do not confirm (DANGEROUS)
      mix release.clean --implode --no-confirm

  """
  @shortdoc "Clean up any release-related files"

  use     Mix.Task
  alias   ReleaseManager.Utils.Logger
  import  ReleaseManager.Utils

  def run(args) do
    if Mix.Project.umbrella? do
      config = [build_path: Mix.Project.build_path]
      for %Mix.Dep{app: app, opts: opts} <- Mix.Dep.Umbrella.loaded do
        Mix.Project.in_project(app, opts[:path], config, fn _ -> do_run(args) end)
      end
    else
      do_run(args)
    end
  end

  def do_run(args) do
    app     = Mix.Project.config |> Keyword.get(:app)
    version = Mix.Project.config |> Keyword.get(:version)
    Logger.debug "Removing release files for #{app}-#{version}..."
    cond do
      "--implode" in args ->
        if "--no-confirm" in args or confirm_implode?(app) do
          do_cleanup :all
          execute_after_hooks(args)
          Logger.info "All release files for #{app}-#{version} were removed successfully!"
        end
      true ->
        do_cleanup :build
        execute_after_hooks(args)
        Logger.info "The release for #{app}-#{version} has been removed."
    end
  end

  # Clean release build
  def do_cleanup(:build) do
    project   = Mix.Project.config |> Keyword.get(:app) |> Atom.to_string
    version   = Mix.Project.config |> Keyword.get(:version)
    build     = Path.absname("../prod", Mix.Project.build_path)
    release   = rel_dest_path [project, "releases", version]
    releases  = rel_dest_path [project, "releases", "RELEASES"]
    start_erl = rel_dest_path [project, "releases", "start_erl.data"]
    lib       = rel_dest_path [project, "lib", "#{project}-#{version}"]
    relup     = rel_dest_path [project, "relup"]

    if File.exists?(release),   do: File.rm_rf!(release)
    if File.exists?(releases),  do: File.rm_rf!(releases)
    if File.exists?(start_erl), do: File.rm_rf!(start_erl)
    if File.exists?(lib),       do: File.rm_rf!(lib)
    if File.exists?(relup),     do: File.rm_rf!(relup)
    if Mix.env != :prod && File.exists?(build) do
      build
      |> File.ls!
      |> Enum.map(fn dir -> build |> Path.join(dir) end)
      |> Enum.map(&File.rm_rf!/1)
    end
  end
  # Clean up the template files for release generation
  def do_cleanup(:relfiles) do
    rel_files = rel_file_dest_path()
    if File.exists?(rel_files), do: File.rm_rf!(rel_files)
  end
  # Clean up everything
  def do_cleanup(:all) do
    # Execute other clean tasks
    do_cleanup :build

    # Remove release folder
    rel = rel_dest_path()
    if File.exists?(rel), do: File.rm_rf!(rel)
  end

  defp execute_after_hooks(args) do
    plugins = ReleaseManager.Plugin.load_all
    Enum.each plugins, fn plugin ->
      try do
        plugin.after_cleanup(args)
      rescue
        exception ->
          stacktrace = System.stacktrace
          Logger.error "Failed to execute after_cleanup hook for #{plugin}!"
          reraise exception, stacktrace
      end
    end
  end

  defp confirm_implode?(app) do
    IO.puts IO.ANSI.yellow
    msg = """
    THIS WILL REMOVE ALL RELEASES AND RELATED CONFIGURATION FOR #{app |> Atom.to_string |> String.upcase}!
    Are you absolutely sure you want to proceed?
    """
    answer = IO.gets(msg <> " [Yn]: ") |> String.trim_trailing(?\n)
    IO.puts IO.ANSI.reset
    answer =~ ~r/^(Y(es)?)?$/i
  end

end
