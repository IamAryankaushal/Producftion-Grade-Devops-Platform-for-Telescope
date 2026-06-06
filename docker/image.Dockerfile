FROM node:18-alpine3.15

WORKDIR /app

RUN apk add --no-cache python3 make g++ vips-dev

RUN npm install -g pnpm@9.15.9

COPY package.json ./

RUN npm_config_platform=linuxmusl \
    npm_config_arch=x64 \
    pnpm install --prod --ignore-scripts=false

COPY . .

USER node

CMD ["node", "src/server.js"]
