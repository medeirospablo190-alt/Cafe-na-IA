ALTER TABLE app1_feed_posts
  ADD COLUMN IF NOT EXISTS comment_text TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conname = 'app1_feed_posts_comment_length_check'
       AND conrelid = 'app1_feed_posts'::regclass
  ) THEN
    ALTER TABLE app1_feed_posts
      ADD CONSTRAINT app1_feed_posts_comment_length_check
      CHECK (comment_text IS NULL OR char_length(comment_text) <= 500);
  END IF;
END;
$$;
