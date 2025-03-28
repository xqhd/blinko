FROM node:22-alpine AS builder

RUN apk add --no-cache \
    python3 \
    python3-dev \
    py3-setuptools \
    make \
    g++ \
    gcc \
    git \
    openssl-dev \
    build-base

WORKDIR /app

ENV NEXT_PRIVATE_STANDALONE=true

COPY package.json pnpm-lock.yaml ./

RUN npm install -g pnpm@9.12.2 && \
    if [ "$USE_MIRROR" = "true" ]; then \
        echo "Using mirror registry..." && \
        npm install -g nrm && \
        nrm use taobao; \
    fi && \
    pnpm install --ignore-scripts=tree-sitter

COPY prisma ./prisma
RUN npx prisma generate

COPY . .
RUN pnpm build
RUN pnpm build-seed
# remove onnxruntime-node
RUN find /app -type d -name "onnxruntime-node*" -exec rm -rf {} +

FROM node:22-alpine AS runner

RUN apk add --no-cache \
    curl \
    tzdata \
    openssl


WORKDIR /app

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/seed.js ./seed.js
COPY --from=builder /app/resetpassword.js ./resetpassword.js

# copy .pnpm files
RUN --mount=type=bind,from=builder,source=/app/node_modules/.pnpm,target=/src \
    for dir in $(find /src -maxdepth 1 -type d -name "@prisma*" -o -name "prisma*" -o -name "@libsql+linux-arm64-gnu*" -o -name "@libsql+linux-x64-musl*"); do \
        target_dir="./node_modules/.pnpm/$(basename "$dir")"; \
        if [ ! -d "$target_dir" ]; then \
            mkdir -p "$target_dir"; \
            echo "Copying $dir to $target_dir"; \
            cp -r "$dir"/* "$target_dir"/; \
        else \
            echo "Skipping $dir, already exists"; \
        fi; \
    done

COPY --from=builder /app/node_modules/@libsql ./node_modules/@libsql
COPY --from=builder /app/node_modules/.bin/prisma ./node_modules/.bin/prisma
COPY --from=builder /app/node_modules/prisma ./node_modules/prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma

ENV NODE_ENV=production \
    PORT=1111 \
    HOSTNAME=0.0.0.0

EXPOSE 1111

CMD ["sh", "-c", "npx prisma migrate deploy && node seed.js && node server.js"]
