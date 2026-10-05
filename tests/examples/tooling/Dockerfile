# syntax=docker/dockerfile:1
FROM ruby:3.4-slim AS build

ARG BUNDLE_WITHOUT="development:test"
ENV LANG=C.UTF-8 \
    RAILS_ENV=production

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 && \
    rm -rf /usr/local/bundle/cache

COPY . .

FROM ruby:3.4-slim
COPY --from=build /app /app
EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
