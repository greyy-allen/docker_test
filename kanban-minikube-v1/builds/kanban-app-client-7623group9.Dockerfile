FROM node:latest

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY package.json /usr/src/app
COPY yarn.lock /usr/src/app
RUN npm install --force

RUN mkdir -p /usr/src/app/src
RUN mkdir -p /usr/src/app/public
COPY src /usr/src/app/src
COPY public /usr/src/app/public

ARG REACT_APP_AWS_IPV4
ENV REACT_APP_AWS_IPV4=$REACT_APP_AWS_IPV4
RUN npm run build --omit=dev
RUN npm install -g serve

EXPOSE 3000
CMD ["serve", "-s", "build"]