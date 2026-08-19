-- 부하테스트용 계정 4000개 일괄 생성
-- loadtest0001 ~ loadtest4000 / 비밀번호는 전부 test1234 (기존 data.sql의 testuser01과 동일한 bcrypt 해시 재사용)
-- 회원가입/이메일인증 API를 거치지 않고 DB에 직접 넣음 — 부하테스트는 "가입이 되는지"가 아니라
-- "로그인 이후 흐름이 몰렸을 때 버티는지"를 보는 것이므로 가입 단계는 사전에 시드로 대체.
--
-- 실행: mysql -h <host> -u root -p qket < seed_test_accounts.sql
-- (로컬 docker: docker exec -i qket-mysql mysql -uroot -p1234 qket < seed_test_accounts.sql)

SET SESSION cte_max_recursion_depth = 4000;

INSERT INTO USERS (user_id, user_nm, pwd, user_email, role_id, user_status)
WITH RECURSIVE seq_cte (seq) AS (
    SELECT 1
    UNION ALL
    SELECT seq + 1 FROM seq_cte WHERE seq < 4000
)
SELECT
    CONCAT('loadtest', LPAD(seq, 4, '0')),
    CONCAT('부하테스트유저', LPAD(seq, 4, '0')),
    '$2b$10$hWBKmcDTCeEpTSo69AszSOq83qcpV.y7HJwWtweymXyxLmL7kD4Am',
    CONCAT('loadtest', LPAD(seq, 4, '0'), '@qket.com'),
    1,
    'ACTIVE'
FROM seq_cte
ON DUPLICATE KEY UPDATE user_id = user_id;  -- 재실행해도 에러 없이 건너뜀

SELECT COUNT(*) AS seeded_count FROM USERS WHERE user_id LIKE 'loadtest%';
