defmodule PlugRest.Router do
  @moduledoc ~S"""
  A DSL to supplement Plug Router with a resource-oriented routing algorithm.

  It provides a macro to generate routes that dispatch to specific
  resource handlers. For example:

      defmodule MyApp.Router do
        use PlugRest.Router

        resource "/pages/:page", PageResource
      end

  The `resource/2` macro accepts a request of format `"/pages/VALUE"` and
  dispatches it to the `PageResource` module, which must adopt the
  `PlugRest.Resource` behaviour by implementing one or more of the callbacks
  which describe the resource.

  The macro accepts an optional initial state for the resource. For example:

      resource "/pages/:page", PageResource, %{some_option: true}

  Because the router builds on Plug's own Router, you can add additional
  plugs into the pipeline. See the documentation for `Plug.Router` for
  more information.


  ## Routes

      resource "/hello", HelloResource

  The example above will route any requests for "/hello" to the
  `HelloResource` module.

  A route can also specify parameters which will be available to the
  resource:

      resource "/hello/:name", HelloResource

  The value of the dynamic path segment can be read inside the
  `HelloResource` module:

      %{"name" => name} = read_path_params(conn)

  Routes allow globbing, which will match the end of the route. The glob
  can be discarded:

      # matches all routes starting with /hello
      resource "/hello/*_rest", HelloResource

  Or saved as a param for the resource to read:

      # matches all routes starting with /hello and saves the rest
      resource "/hello/*rest", HelloResource

  If we make a request to "/hello/value" then `read_path_params/1` will
  return:

      %{"rest" => ["value"]}

  If we make a request to "/hello/value/extra" then `read_path_params/1`
  will return:

      %{"rest" => ["value", "extra"]}
  """


  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      use Plug.Router
      import PlugRest.Router
      @before_compile PlugRest.Router

      plug :match
      plug :dispatch
    end
  end


  @doc false
  defmacro __before_compile__(_env) do
    quote do
      import Plug.Router, only: [match: 2]
      match _ do
        send_resp(var!(conn), 404, "")
      end
    end
  end


  ## Resource

  @doc """
  Main API to define resource routes.

  It accepts an expression representing the path, the name of a module
  representing the resource, and an optional initial state.

  ## Examples

      resource "/pages/:page", PageResource, %{some_option: true}

  """
  defmacro resource(path, handler, handler_state \\ []) do
    add_resource(path, handler, handler_state)
  end

  ## Compiles the resource into a match macro from Plug.Router
  defp add_resource(path, handler, handler_state) do
    {vars, _match} = Plug.Router.Utils.build_path_match(path)

    # Transform the list of path variables into a data structure that will
    # bind to real path parameters inside the macro, like:
    # `[{"bar", {:bar, [], nil}}]`. The first step creates the binding. The
    # second removes any underscored variables, since using them in the macro
    # will raise a compiler warning.
    binding =
      vars
      |> Enum.map(fn(var) -> {Atom.to_string(var), Macro.var(var, nil)} end)
      |> Enum.filter(fn({var, _macro}) -> String.at(var, 0) !== "_" end)

    quote do
      match unquote(path) do

        params =
          Enum.reduce(
            unquote(binding),
            %{},
            fn({k,v}, p) -> Map.put(p, k, v) end
          )

        # Save dynamic path segments into private connection storage
        conn2 = var!(conn) |> PlugRest.Conn.put_path_params(params)

        PlugRest.Resource.upgrade(conn2, unquote(handler), unquote(handler_state))
      end
    end
  end
end
