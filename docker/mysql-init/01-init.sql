-- ─────────────────────────────────────────────────────────────────────────────
-- SIA MySQL Init Script
-- Executed ONCE when the MySQL container is first created (fresh volume).
-- Sets up charset, creates/grants the app user explicitly.
-- ─────────────────────────────────────────────────────────────────────────────

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- Ensure the SIA database uses the correct character set
ALTER DATABASE `sia` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Explicitly create sia_user with native password auth and grant all privileges
-- (MySQL MYSQL_USER env var creates the user but sometimes misses WITH GRANT OPTION)
CREATE USER IF NOT EXISTS 'sia_user'@'%'
    IDENTIFIED WITH mysql_native_password BY 'sia_password';
GRANT ALL PRIVILEGES ON `sia`.* TO 'sia_user'@'%' WITH GRANT OPTION;

-- Allow root to connect from any Docker bridge IP (for debugging/phpMyAdmin)
CREATE USER IF NOT EXISTS 'root'@'%'
    IDENTIFIED WITH mysql_native_password BY 'root_secret';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

FLUSH PRIVILEGES;
