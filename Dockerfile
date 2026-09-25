FROM ruby:3.2

RUN apt-get update && \
	apt-get install -y --no-install-recommends libxmlsec1-dev && \
	rm -rf /var/lib/apt/lists/*

RUN mkdir /app
WORKDIR /app
COPY Gemfile Gemfile.lock ruby-saml2-sans.gemspec /app/
COPY lib/saml2/version.rb /app/lib/saml2/

RUN bundle config --local frozen true && bundle install -j 4

COPY . /app/
