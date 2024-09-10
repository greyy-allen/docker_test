# gu-7623ict-secdevops-a1-group9-aws 

Griffith University MIT T2 2024
7623ICT Secure Development Operations
Group 9
Assignment 1 - Containerise a Full-stack Project & Code Vulnerability Review
(Container/Kubernetes/Red Team Ops in AWS)

Docker Compose -> Minikube -> Security Assessment


## First Contact / Code Audit

client
    -> npm install
    -> npm run start (aka yarn start)
server
    -> npm install
    -> .env in root
        MONGODB_URL=mongodb://127.0.0.1:27017/gukanbantest
        PORT=5000
        PASSWORD_SECRET_KEY= (random string for now, not sure if they're actually using this)
        TOKEN_SECRET_KEY= (random string for now, not sure if they're actually using this)
    -> npm run start (aka yarn start)

@LINE 4 [code project]/client/src/api/axiosClient.js
    const baseUrl = 'http://127.0.0.1:5000/api/v1/'

@LINE 33 reading .env [code project]/server/bin/www.js
    mongoose.connect(process.env.MONGODB_URL).then(() => {

@LINE 20 reading .env [code project]/server/bin/www.js
    const port = normalizePort(process.env.PORT || '3000');


## Containerisation / AWS Prep (Docker Compose and Minikube/Kubernetes)

- Create AWS EC2 t2.medium Ubuntu instance with docker 10-15GB storage if using separate instances for compose and Minikube/Kubernetes
    - 20-25+GB if running 2 "sets" of compose/kube images on a single instance and you don't want to clear caches all the time
- Make a directory in the /srv directory (loosely following Linux Filesystem Hierarchy Standard for this) for this project
    - sudo mkdir gu-7623ict-secdevops-a1-group9-aws
    - cd into the project directory and clone the web app GitHub repository
        - cd /srv/gu-7623ict-secdevops-a1-group9-aws
        - git clone [code project.git]
        - create rest of the directories and files

Directory structure should look like this:
(ec2 root)/srv/
    gu-7623ict-secdevops-a1-group9-aws/
        [code project]/
        kanban-compose-v2/
            builds/
            secrets/
                ssl/
                    localhost/
                    RootCA/
        kanban-minikube-v1/
            builds
            configmap
            secrets/
                ssl/
                    localhost/
                    RootCA/
	optional/


## Docker Compose v2 (2024-09-06 Friday)

kanban-compose-v1 demo run locally (now deprecated), v2 organised for local Docker installations and AWS EC2 instances

- kanban-compose-v2 **does not** require a .env in the [code project] server directory, "process.env.VAR" calls in NODE.js read Linux environment variables inside the container injected via Docker compose config

Use gu-7623ict-secdevops-a1-group9-aws as the top-level (working) directory and run:
- docker compose -f "kanban-compose-v2.yml" build
- docker compose -f "kanban-compose-v2.yml" up

Visit the EC2 public IP address - check connectivity, logs, and application functionality 


### Troubleshooting the original dev code design choices, adding Proxy Networking

Your API calls aren't working because the original dev hardcoded calls to localhost for the API so when compose runs:
 - Docker binds to ports we request (80/443/8081)
 - Frontend is served with the public IPV4
    - the React code is already built and has no way of updating (itself) dynamically at runtime, so the website "works" until requests with the hardcoded API calls are used
    - the browser (mis)interprets the request to the "your computer" localhost because it's just parsing the API code as-is
    - the API code never interacts with the backend when this happens

There are 2 options to work around this immediately:
- short-term fix, hardcode swap/edit:
    - [code project]/client/src/api/axiosClient.js @@ LINE 4
        FROM:   const baseUrl = 'http://127.0.0.1:5000/api/v1/'
        TO:     const baseUrl = 'https://[AWS PUBLIC IP]/api/v1/'
- Automate (partially) and prepare for CI/CD and pipelines with more environment variables

EC2 Ubuntu instances are provisioned with the "ec2metadata" utility that gives us the "outside info inside", stuff that you've probably been copy/pasting so far, accessible for use programatically without having to take big risks grepping or awking "ip -a" or hostname string outputs etc.

- Check your file/relative paths are correct in config files
- Use the gu-7623ict-secdevops-a1-group9-aws directory as the top-level (working) directory
- code edit:
    - [code project]/client/src/api/axiosClient.js @@ LINE 4
        FROM:   const baseUrl = 'https://[AWS PUBLIC IP]/api/v1/'
        TO:     const baseUrl = `https://${process.env.REACT_APP_AWS_IPV4}/api/v1/` (use template literals to interpolate the $)
    - "process.env.VAR" calls in NODE.js read Linux environment variables inside the container injected via Docker compose config
- Now try:
    - export AWS_IPV4=$(ec2metadata --public-ipv4) && docker compose -f "kanban-compose-v2.yml" build
    - docker compose -f "kanban-compose-v2.yml" up
    - restart your instance/lab to get a different public IP and try the export/build/up steps again, the public IP should be passed into every new build from now on using this setup and config when it changes


## Minikube

- Uses process.env.VAR API method
- Switch to the Minikube Docker environment
- Minkube/Kubernetes doesn't build for us (need to use a pod/service for this - out of scope for assignment)
- (Re)build images manually using the Docker service bundled with Minikube after switching Docker environment

kanban-manifest-v1 groups similar/related containers/services together as discussed in lectures etc
- 2 pods, 5 containers (1x2 + 1x3)
- most documentation and what I'd do IRL (and in my lab with k3s) is separate each container into its own pod (5 pods - 1x5) to scale out/up easier or replace the nginx proxy with Ingress/LoadBlancer according to AWS online docs 

build command format: docker build -f(ile) [dockerfile with build instructions] [context aka location of files to be containerised] -t(ag) [tag info] [--build-arg CLI env pass without Docker Compose]


### Build Images

- Use the gu-7623ict-secdevops-a1-group9-aws directory as the top-level (working) directory:

// Build frontend Docker image and pass the AWS public IP in 
- Code edit frontend if [code project] has been pulled from GitHub again
export AWS_IPV4=$(ec2metadata --public-ipv4)
docker build -f "kanban-minikube-v1/builds/kanban-app-client-7623group9.Dockerfile" ./fullstack-kanban-app/client -t "gu-7623ict-g9/kanban-app-client-7623group9:v2" --build-arg REACT_APP_AWS_IPV4=${AWS_IPV4}

docker build -f "kanban-minikube-v1/builds/kanban-app-server-7623group9.Dockerfile" ./fullstack-kanban-app/server -t "gu-7623ict-g9/kanban-app-server-7623group9:v2"


### Decoupling config from nginx Docker image, reducing reliance on build steps (config as code philosophy)

We don't need to build a custom image with nginx - we can pull the "stock" nginx image and add/"overlay" our config and deploy:
- Use of Kubernetes Secrets to create "Secrets" objects so Minikube/K8s can load and interact with the SSL cert/key into the reverse proxy container via config directives
    - Generate your SSL credentials first if you don't have any
    - kubectl create secret tls [name of secret] --cert=[path] --key[path]
    - localhost.* files are refereced using the filenames tls.crt and tls.key within the container when mounted using the manifest

kubectl create secret tls kanban-proxy-rev-tls \
--cert=kanban-minikube-v1/secrets/ssl/localhost/localhost.crt \
--key=kanban-minikube-v1/secrets/ssl/localhost/localhost.key

kubectl describe secret "kanban-proxy-rev-tls"

- Use of ConfigMap objects/spec to make nginx config "portable" between pods and environments (if we were in a business setting with dev/stage/prod etc)
    - Entire nginx config now stored in ConfigMap file/object
        - kanban-minikube-v1/configmap/config-nginx-kanban-proxy-rev.yml
        - need to "create/register" the ConfigMap object using kubectl
        - replaced references to localhost.* with tls.* so mounted TLS K8s Secrets are read

kubectl apply -f "kanban-minikube-v1/configmap/config-nginx-kanban-proxy-rev.yml"


### Deploy to AWS EC2 with public IPs

Requires compose/minikube + security group config (inbound+outbound) + security group assigned to EC2 instance
    - Use the gu-7623ict-secdevops-a1-group9-aws directory as the top-level (working) directory:

kubectl apply -f "kanban-manifest-v1.yml"
kubectl get all

- kanban-manifest-v1 relies on Minikube forwarding/tunneling (same as labs) so far to expose publically
    - use tunnneling with bind option if prompted/denied when trying to use ports under 1000 on your EC2 instance
    - minikube tunnel --bind-address=0.0.0.0 

If deployment goes well, visit the EC2 public IP address - check connectivity, logs, and application functionality

TBA better/alternate methods of doing this (open to all suggestions pls)


## For later / Sec Audit

- node container builds targeting latest version -> should only use even nodejs ver numbers with LTS for security patched/supported builds in prod
    - add args and switch to Dockerfiles like ARG NODE_VERSION="2x" and FROM node:NODE_VERSION
- React nodejs prod build could be moved to multi stage build targeting nginx HTTP server (Dockerfile included in optiona director)
- Secrets currently underutilized for credentials and default config


### Kubernetes Ingress, LoadBalancers "Proper Prod"

"Proper Prod" TBA -Need more info RE AWS permissions to expose K8s without using portforwarding/tunneling
LoadBalancer IPs -> Security Group IN -> (Security Group OUT <-> Ingress/Reverse Proxy OR direct to NodePort) -> Services/Service Mesh -> Pods 