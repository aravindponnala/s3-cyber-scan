CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE jobs (
    job_id     uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    bucket     text NOT NULL,
    prefix     text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TYPE job_object_status AS ENUM ('queued','processing','succeeded','failed');

CREATE TABLE job_objects (
    job_id     uuid NOT NULL,
    bucket     text NOT NULL,
    key        text NOT NULL,
    etag       text NOT NULL,
    status     job_object_status NOT NULL DEFAULT 'queued',
    last_error text,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (job_id, bucket, key, etag),
    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE
);

CREATE TABLE findings (
    id           bigserial PRIMARY KEY,
    job_id       uuid NOT NULL,
    bucket       text NOT NULL,
    key         text NOT NULL,
    detector     text NOT NULL,
    masked_match text NOT NULL,
    context      text,
    byte_offset  int,
    created_at   timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX findings_dedupe_idx
ON findings (bucket, key, etag, detector, byte_offset);
