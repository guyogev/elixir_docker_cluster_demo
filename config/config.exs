# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :logger, format: "[$level] $message\n",
  backends: [{LoggerFileBackend, :log}, :console]

config :logger, :log,
  path: "/tmp/log/cluster.log",
  level: :debug