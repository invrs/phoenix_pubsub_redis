defmodule Phoenix.PubSub.Redis do
  use Supervisor

  @moduledoc """
  Phoenix PubSub adapter based on Redis.

  To use Redis as your PubSub adapter, simply add it to your Endpoint's config:

      config :my_app, MyApp.Endpiont,
        pubsub: [adapter: Phoenix.PubSub.Redis,
                 host: "192.168.1.100"]

  You will also need to add `:phoenix_pubsub_redis` to your deps:

      defp deps do
        [{:phoenix_pubsub_redis, "~> 1.0.0"}]
      end

  And also add `:phoenix_pubsub_redis` to your list of applications:

      def application do
        [mod: {MyApp, []},
         applications: [..., :phoenix, :phoenix_pubsub_redis]]
      end

  ## Options

    * `:url` - The url to the redis server ie: `redis://username:password@host:port`
    * `:name` - The required name to register the PubSub processes, ie: `MyApp.PubSub`
    * `:host` - The redis-server host IP, defaults `"127.0.0.1"`
    * `:port` - The redis-server port, defaults `6379`
    * `:password` - The redis-server password, defaults `""`
    * `:redis_pool_size` - The size of hte redis connection pool. Defaults `5`
    * `:pool_size` - Both the size of the local pubsub server pool and subscriber
      shard size. Defaults `1`. A single pool is often enough for most use-cases,
      but for high subscriber counts on a single topic or greater than 1M
      clients, a pool size equal to the number of schedulers (cores) is a well
      rounded size.

  """

  @redis_pool_size 5
  @defaults [host: "127.0.0.1", port: 6379]


  def start_link(name, opts) do
    supervisor_name = Module.concat(name, Supervisor)
    Supervisor.start_link(__MODULE__, [name, opts], name: supervisor_name)
  end

  @doc false
  def init([server_name, opts]) do
    pool_size = Keyword.fetch!(opts, :pool_size)
    if opts[:url] do
      info = URI.parse(opts[:url])
      destructure [username, password], String.split(info.userinfo, ":")
      opts = Keyword.merge(opts, password: password, username: username, host: info.host, port: info.port)
    end

    opts = Keyword.merge(@defaults, opts)
    opts = Keyword.merge(opts, host: String.to_char_list(opts[:host]))
    if pass = opts[:password] do
      opts = Keyword.put(opts, :pass, String.to_char_list(pass))
    end

    pool_name   = Module.concat(server_name, Pool)
    namespace   = redis_namespace(server_name)
    node_ref    = :crypto.strong_rand_bytes(24)
    server_opts = Keyword.merge(opts, name: server_name,
                                      server_name: server_name,
                                      pool_name: pool_name,
                                      namespace: namespace,
                                      node_ref: node_ref)
    pool_opts = [
      name: {:local, pool_name},
      worker_module: Phoenix.PubSub.RedisConn,
      size: opts[:redis_pool_size] || @redis_pool_size,
      max_overflow: 0
    ]

    dispatch_rules = [{:broadcast, Phoenix.PubSub.RedisServer,
                                   [pool_name, pool_size, namespace, node_ref]}]

    children = [
      supervisor(Phoenix.PubSub.LocalSupervisor, [server_name, pool_size, dispatch_rules]),
      worker(Phoenix.PubSub.RedisServer, [server_opts]),
      :poolboy.child_spec(pool_name, pool_opts, [opts]),
    ]

    supervise children, strategy: :rest_for_one
  end

  defp redis_namespace(server_name), do: "phx:#{server_name}"
end
