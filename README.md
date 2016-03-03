#Dockering an Elixir cluster <img src="./images/elixir.png" alt="Elixir" width="100" float:'right'/><img src="./images/docker-compose.png" alt="docker-compose" width="100" float:'left' />

------------------------------------------------------------------------------------------------------------------------

Distributed systems are deployed on multiple machines/VM's of curse. But while developing, we would like to simulate 
such distributed system on a single machine. At this doc, we'll demonstrate such setup.


We'll use **Elixir** to create a node. Elixir is a dynamic, functional language designed for building scalable and maintainable applications.
It leverages the Erlang VM, known for running low-latency, distributed and fault-tolerant systems, while also being successfully used in web development and the embedded software domain.


**Docker** will deploy our nodes. Docker containers wrap up a piece of software in a complete file-system that contains everything it needs to run: code, runtime, system tools, system libraries – anything you can install on a server. This guarantees that it will always run the same, regardless of the environment it is running in.


A Basic Node
----------
#### General consent:
A node will have only 2 tasks:
 - Seek other nodes.
 - Write to log file.

Our cluster needs some kind of cross-machine node registry.
At this example, we'll use the host's local file system, but this can easily implemented for production apps using something like S3 or any other synced FS service.

At this stage, we'll assume that each node starts with the Erlang long-name `uniqe_name@public_ip`.

Every node will register itself at the cluster registry by creating a file under his name. It will also keep a time-stamp so we'll know when the node was last active.

```Elixir
  @sync_dir "/tmp/sync_dir/"

  def sign_as_active_node do
    File.mkdir_p @sync_dir
    {:ok, file} = File.open(path, [:write])
    IO.binwrite file, time_now_as_string
    File.close file
  end

  def path do
    @sync_dir <> Atom.to_string(Node.self)
  end
```

In order to find out other registered nodes, each node will try to ping the others listed at that folder.

```Elixir
  def check_active_nodes do
    active_nodes
      |> Enum.map(&(String.to_atom &1))
      |> Enum.map(&({&1, Node.ping(&1) == :pong}))
  end

  def active_nodes do
    {:ok, active_members} = File.ls(@sync_dir)
    active_members
  end
```

We'll bundle it all into a simple recursive main loop that is triggered when the app boots, and thats it! We have a distributed system with a pulse check!
```Elixir
  def loop do
    sign_as_active_node
    status = inspect check_active_nodes
    Logger.info(Atom.to_string(Node.self) <> status)
    :timer.sleep(@interval)
    loop
  end
```

This is a very basic setup. We can expand it to any distributed system architectures.

Lets see the nodes in action. We'll start some nodes with a unique longname & predefined cookie.
```Bash
  $> elixir --name a1@127.0.0.1 --cookie cookie -S mix
  $> elixir --name a2@127.0.0.1 --cookie cookie -S mix
  $> cat /tmp/log/cluster.log

  18:51:29.277 [info] a2@127.0.0.1["a1@127.0.0.1": true, "a2@127.0.0.1": true]
  18:51:29.974 [info] a1@127.0.0.1["a1@127.0.0.1": true, "a2@127.0.0.1": true]
  18:51:30.281 [info] a2@127.0.0.1["a1@127.0.0.1": true, "a2@127.0.0.1": true]
```

Dockering the Node
------------------

Docker builds images automatically by reading the instructions from a Dockerfile. Lets create one.

We'll use an clean Ubuntu 14.04 image

```Bash
FROM ubuntu:14.04
```

Install Elixir and add our app.

```Bash
# Install Erlang
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    unzip \
    libwxbase3.0 \
    libwxgtk2.8-0 \
    build-essential
RUN wget https://packages.erlang-solutions.com/erlang/esl-erlang/FLAVOUR_1_general/esl-erlang_18.2-1~ubuntu~precise_amd64.deb
RUN dpkg -i esl-erlang_18.2-1~ubuntu~precise_amd64.deb && apt-get install -f

# Install Elixir
RUN wget https://github.com/elixir-lang/elixir/releases/download/v1.2.1/Precompiled.zip
RUN mkdir -p /usr/local/elixir
RUN cd /usr/local/elixir && unzip /Precompiled

# Install hex & rebar
RUN bash -c "mix local.hex <<< 'Y'"
RUN bash -c "mix local.rebar <<< 'Y'"
```

Add our app to the container
```
ADD . /app
WORKDIR /app

RUN mix deps.get
RUN mix compile
```

We want the app to start by default when the container boots

```Bash
CMD ./run.sh
```

The run.sh script

```
str=`date -Ins | md5sum`
name=${str:0:10}

elixir --name $name@$127.0.0.1 --cookie cookie -S mix
```

Now we can run nodes in containers.

```Bash
$> docker build -t spectory/iex_cluster .
$> docker run -it spectory/iex_cluster

08:12:56.821 [info]  1810ea8527@127.0.0.1["1810ea8527@127.0.0.1": true]
08:12:57.824 [info]  1810ea8527@127.0.0.1["1810ea8527@127.0.0.1": true]

```

Even though we can deploy a multiple nodes, that won't create a cluster because each container is isolated form the others.

Deploying a cluster
-------------------
When deploying production apps to cloud services such as AWS or Gcloud, we usually create a network, and run our system under a subnet. We want to simulate such setup too and run all our nodes under the same subnet.

Luckily, the good guys of Docker supplied us with an easy setup for just that - Docker-Compose.

**Docker Compose** is a tool for defining and running multi-container Docker applications. With Compose, you use a a single file to configure all of the app’s services. Then, using a single command, you create and start all the services from your configuration.

Here is our docker-compose file:
```yml
version: '2'

services:
  node:
    build:
      context: ./
    volumes:
    - /tmp:/tmp
```

As we mentioned above, we use the host's file-system as our nodes registry. Thats why we share the /tmp folder between all our nodes & the host by using the `volume` option.

Thats it. Docker-Compose is taking care of all the hard stuff for us. Docker-Compose will create a network, and each container that boots will get an IP at that network.

If you think that was easy, see how we deploy a cluster...

We need each node to register under his public IP, so we'll edit our run.sh

```Bash
ip=`ip a | grep global | grep -oE '((1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])'`
str=`date -Ins | md5sum`
name=${str:0:10}

elixir --name $name@$ip --cookie cookie -S mix
```

And now, let the magic happen:
```Bash
$> docker-compose up -d
node_1 | 08:25:55.412 [info]  ab4b316c90@172.19.0.2["ab4b316c90@172.19.0.2": true]
```

Thats cool, but a single node is pretty boring.

```Bash
$> docker-compose scale node=5
node_2 | 08:27:40.557 [info]  7c57022cc5@172.19.0.6["2cf48db6cf@172.19.0.5": true, "2499eafece@172.19.0.4": true, "ab4b316c90@172.19.0.2": true, "7c57022cc5@172.19.0.6": true, "8caff4aac0@172.19.0.3": true]
node_3 | 08:27:40.567 [info]  2cf48db6cf@172.19.0.5["2cf48db6cf@172.19.0.5": true, "2499eafece@172.19.0.4": true, "ab4b316c90@172.19.0.2": true, "7c57022cc5@172.19.0.6": true, "8caff4aac0@172.19.0.3": true]
node_1 | 08:27:40.717 [info]  ab4b316c90@172.19.0.2["2cf48db6cf@172.19.0.5": true, "2499eafece@172.19.0.4": true, "ab4b316c90@172.19.0.2": true, "7c57022cc5@172.19.0.6": true, "8caff4aac0@172.19.0.3": true]
node_5 | 08:27:41.224 [info]  8caff4aac0@172.19.0.3["2cf48db6cf@172.19.0.5": true, "2499eafece@172.19.0.4": true, "ab4b316c90@172.19.0.2": true, "7c57022cc5@172.19.0.6": true, "8caff4aac0@172.19.0.3": true]
node_4 | 08:27:41.382 [info]  2499eafece@172.19.0.4["2cf48db6cf@172.19.0.5": true, "2499eafece@172.19.0.4": true, "ab4b316c90@172.19.0.2": true, "7c57022cc5@172.19.0.6": true, "8caff4aac0@172.19.0.3": true]

```
Take it up to 11!
```Bash
$> docker-compose scale node=11
node_11 | 08:35:06.617 [info]  abc209f0fb@172.19.0.4["e1da961a15@172.19.0.8": true, "3bf905d667@172.19.0.2": true, "abc209f0fb@172.19.0.4": true, "4007e826da@172.19.0.7": true, "6f396d19ef@172.19.0.11": true, "530b53e06f@172.19.0.3": true, "838d8ec661@172.19.0.10": true, "b151f009f0@172.19.0.12": true, "fa6e2479bd@172.19.0.5": true, "3413e458df@172.19.0.9": true, "3a8ba306cf@172.19.0.6": true]
node_2  | 08:35:06.628 [info]  530b53e06f@172.19.0.3["e1da961a15@172.19.0.8": true, "3bf905d667@172.19.0.2": true, "abc209f0fb@172.19.0.4": true, "4007e826da@172.19.0.7": true, "6f396d19ef@172.19.0.11": true, "530b53e06f@172.19.0.3": true, "838d8ec661@172.19.0.10": true, "b151f009f0@172.19.0.12": true, "fa6e2479bd@172.19.0.5": true, "3413e458df@172.19.0.9": true, "3a8ba306cf@172.19.0.6": true]
node_4  | 08:35:06.628 [info]  3413e458df@172.19.0.9["e1da961a15@172.19.0.8": true, "3bf905d667@172.19.0.2": true, "abc209f0fb@172.19.0.4": true, "4007e826da@172.19.0.7": true, "6f396d19ef@172.19.0.11": true, "530b53e06f@172.19.0.3": true, "838d8ec661@172.19.0.10": true, "b151f009f0@172.19.0.12": true, "fa6e2479bd@172.19.0.5": true, "3413e458df@172.19.0.9": true, "3a8ba306cf@172.19.0.6": true]
node_6  | 08:35:06.632 [info]  e1da961a15@172.19.0.8["e1da961a15@172.19.0.8": true, "3bf905d667@172.19.0.2": true, "abc209f0fb@172.19.0.4": true, "4007e826da@172.19.0.7": true, "6f396d19ef@172.19.0.11": true, "530b53e06f@172.19.0.3": true, "838d8ec661@172.19.0.10": true, "b151f009f0@172.19.0.12": true, "fa6e2479bd@172.19.0.5": true, "3413e458df@172.19.0.9": true, "3a8ba306cf@172.19.0.6": true]
node_8  | 08:35:06.647 [info]  4007e826da@172.19.0.7["e1da961a15@172.19.0.8": true, "3bf905d667@172.19.0.2": true, "abc209f0fb@172.19.0.4": true, "4007e826da@172.19.0.7": true, "6f396d19ef@172.19.0.11": true, "530b53e06f@172.19.0.3": true, "838d8ec661@172.19.0.10": true, "b151f009f0@172.19.0.12": true, "fa6e2479bd@172.19.0.5": true, "3413e458df@172.19.0.9": true, "3a8ba306cf@172.19.0.6": true]
node_7  | 08:35:06.647 [info]  6f396d19ef@172.19.0.11["e1da961a15@172.19.0.8": true, "3bf905d667@172.19.0.2": true, "abc209f0fb@172.19.0.4": true, "4007e826da@172.19.0.7": true, "6f396d19ef@172.19.0.11": true, "530b53e06f@172.19.0.3": true, "838d8ec661@172.19.0.10": true, "b151f009f0@172.19.0.12": true, "fa6e2479bd@172.19.0.5": true, "3413e458df@172.19.0.9": true, "3a8ba306cf@172.19.0.6": true]
node_3  | 08:35:06.649 [info]  3bf905d667@172.19.0.2["e1da961a15@172.19.0.8": true, "3bf905d667@172.19.0.2": true, "abc209f0fb@172.19.0.4": true, "4007e826da@172.19.0.7": true, "6f396d19ef@172.19.0.11": true, "530b53e06f@172.19.0.3": true, "838d8ec661@172.19.0.10": true, "b151f009f0@172.19.0.12": true, "fa6e2479bd@172.19.0.5": true, "3413e458df@172.19.0.9": true, "3a8ba306cf@172.19.0.6": true]
node_9  | 08:35:06.653 [info]  3a8ba306cf@172.19.0.6["e1da961a15@172.19.0.8": true, "3bf905d667@172.19.0.2": true, "abc209f0fb@172.19.0.4": true, "4007e826da@172.19.0.7": true, "6f396d19ef@172.19.0.11": true, "530b53e06f@172.19.0.3": true, "838d8ec661@172.19.0.10": true, "b151f009f0@172.19.0.12": true, "fa6e2479bd@172.19.0.5": true, "3413e458df@172.19.0.9": true, "3a8ba306cf@172.19.0.6": true]
```

Summery
-------
We've create a node using Elixir. Even though it is very basic, it can be expanded to a more interesting fully functional one.
we can also wrap it in as an elixir application and load it into any system as a micro service, making it a distributed one.

We've wrapped our node in a docker containers. This made our node very portable. We can very easily deploy our nodes not only on our dev environment, but also to production. We just need to make sure the containers can access each other at any environment.

We've covered how to simulate a cross machine cluster at a dev environment using docker-compose, which create a network between containers. Compose allows us easily to create, start, stop & scale our cluster.

