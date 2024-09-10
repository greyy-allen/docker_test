### Stage 01 Node/React build

FROM node:latest AS kanbanFrontendBuildStage01

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

###
###
### Stage 02 Nginx build
### 
###

FROM nginx:latest AS kanbanFrontendBuildStage02

WORKDIR /usr/share/nginx
RUN rm -rf "html"
RUN mkdir "html"

WORKDIR /usr/share/nginx/html
COPY --from=kanbanFrontendBuildStage01 /app/build .

EXPOSE 80
ENTRYPOINT ["nginx", "-g", "daemon off;"]
