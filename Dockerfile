FROM crystallang/crystal:0.31.1

RUN shards build --release

CMD ["build/moku"]
