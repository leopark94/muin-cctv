-- Migration: Add active_channels column to stores table
-- Run this in Supabase SQL Editor to update existing database

-- 1. Add active_channels column
ALTER TABLE stores
ADD COLUMN IF NOT EXISTS active_channels INT[] DEFAULT ARRAY[1,2,3,4];

-- 2. Update existing stores with default channels
UPDATE stores
SET active_channels = ARRAY[1,2,3,4]
WHERE active_channels IS NULL;

-- 3. Add comment
COMMENT ON COLUMN stores.active_channels IS '사용할 RTSP 채널 목록 (예: {1,2,3,4})';

-- Verify
SELECT store_id, store_name, rtsp_host, rtsp_port, active_channels, total_channels
FROM stores;
