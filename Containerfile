FROM ruby:3.3-alpine

RUN adduser -D -u 1000 certvis

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development' \
 && bundle install

COPY --chown=certvis:certvis bin/ bin/
COPY --chown=certvis:certvis lib/ lib/
COPY --chown=certvis:certvis public/ public/
COPY --chown=certvis:certvis sites.lst ./

ENV CERTVIS_PORT=8000 \
    CERTVIS_INTERVAL=900

EXPOSE 8000
USER certvis

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD wget -qO- "http://localhost:${CERTVIS_PORT}/certs.json" > /dev/null || exit 1

# Shell form so $CERTVIS_PORT/$CERTVIS_INTERVAL expand; exec replaces the
# shell so certvis (not sh) is PID 1 and receives SIGTERM directly.
CMD ["sh", "-c", "exec bin/certvis --serve --port \"$CERTVIS_PORT\" --interval \"$CERTVIS_INTERVAL\" -v"]
