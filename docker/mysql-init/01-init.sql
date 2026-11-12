-- ─────────────────────────────────────────────────────────────────────────────
-- SIA MySQL Init Script
-- This file is executed once when the MySQL container is first created.
-- It sets up charset, timezone support, and optimal MySQL settings for SIA.
-- ─────────────────────────────────────────────────────────────────────────────

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- Ensure the SIA database uses the correct character set
ALTER DATABASE `sia` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
