FROM ubuntu:14.04

MAINTAINER Guy Yogev <guy@spectory.com>
LABEL description="A simple Elixir node in a self-discovering cluster"

ENV PATH /usr/local/elixir/bin:$PATH
ENV LANG en_US.utf8

# Set up locale
RUN locale-gen "en_US.UTF-8"
RUN dpkg-reconfigure locales
RUN update-locale LC_ALL=en_US.UTF-8

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

ADD . /app
WORKDIR /app

RUN mix deps.get
RUN mix compile

CMD ./run.sh