#!/usr/bin/env python3
"""
Cafe24 OAuth 2.0 Access Token 발급 및 테스트 헬퍼 스크립트
.env 파일의 정보를 사용하여 인가 코드를 입력받고 토큰을 발급받아 .env에 저장합니다.
"""

import os
import sys
import base64
import urllib.parse
import urllib.request
import json
import ssl

ENV_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '.env')

def load_env(filepath):
    config = {}
    if not os.path.exists(filepath):
        return config
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' in line:
                key, val = line.split('=', 1)
                key = key.strip()
                val = val.strip().strip('"').strip("'")
                config[key] = val
    return config

def update_env(filepath, updates):
    lines = []
    updated_keys = set()
    if os.path.exists(filepath):
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                stripped = line.strip()
                if stripped and not stripped.startswith('#') and '=' in stripped:
                    key = stripped.split('=', 1)[0].strip()
                    if key in updates:
                        lines.append(f'{key} = "{updates[key]}"\n')
                        updated_keys.add(key)
                        continue
                lines.append(line)
    
    for key, val in updates.items():
        if key not in updated_keys:
            lines.append(f'{key} = "{val}"\n')

    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(lines)

def main():
    print("=" * 60)
    print("  Cafe24 API 토큰 발급 및 테스트 도구")
    print("=" * 60)

    env = load_env(ENV_PATH)
    mall_id = env.get("Mall_ID", "")
    
    if not mall_id:
        print("[오류] .env 파일에서 Mall_ID를 찾을 수 없습니다.")
        sys.exit(1)

    print(f"\n[1] 쇼핑몰 ID: {mall_id}")
    print("사용할 클라이언트 키를 선택해주세요:")
    print("  1) iOS     (Client_ID_IOS)")
    print("  2) Android (Client_ID_Android)")
    choice = input("선택 [기본값: 1]: ").strip() or "1"

    if choice == "2":
        client_id = env.get("Client_ID_Android", "")
        client_secret = env.get("Client_Secret_Android", "")
        target = "Android"
    else:
        client_id = env.get("Client_ID_IOS", "")
        client_secret = env.get("Client_Secret_IOS", "")
        target = "iOS"

    if not client_id or not client_secret:
        print(f"[오류] .env에 {target}용 Client_ID 또는 Client_Secret이 없습니다.")
        sys.exit(1)

    print(f"\n[선택됨: {target}] Client ID: {client_id}")

    # Redirect URI 확인
    redirect_uri = env.get("Redirect_URI", "")
    if not redirect_uri:
        print("\nCafe24 개발자센터의 앱 설정에 등록된 'Redirect URI'를 입력해주세요.")
        print("(예: https://localhost:8080/oauth/callback 또는 앱 커스텀 스킴)")
        redirect_uri = input("Redirect URI: ").strip()
        if not redirect_uri:
            print("[오류] Redirect URI가 입력되지 않았습니다.")
            sys.exit(1)

    # Scopes
    scopes = env.get("Scopes", "mall.read_product,mall.read_category")

    # PKCE code_verifier 및 code_challenge 생성
    import hashlib
    verifier_bytes = os.urandom(32)
    code_verifier = base64.urlsafe_b64encode(verifier_bytes).decode('utf-8').rstrip('=')
    code_challenge = base64.urlsafe_b64encode(
        hashlib.sha256(code_verifier.encode('utf-8')).digest()
    ).decode('utf-8').rstrip('=')

    # Step 1: 인가 URL 생성 (PKCE 포함)
    auth_params = {
        "response_type": "code",
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
    }
    auth_url = f"https://{mall_id}.cafe24api.com/api/v2/oauth/authorize?{urllib.parse.urlencode(auth_params)}"

    print("\n" + "-" * 60)
    print("📌 아래 브라우저 인증 URL로 이동하여 로그인 및 앱 권한을 승인해주세요:")
    print("-" * 60)
    print(auth_url)
    print("-" * 60)

    print("\n동의 완료 후 브라우저 주소창의 리다이렉트된 전체 URL 또는 code 값을 복사하여 입력해주세요.")
    print("(예: https://suzicnl.com/auth/redirect?code=AbCdEf123... 형태)")
    redirected_input = input("리다이렉트 URL 또는 code: ").strip()

    if not redirected_input:
        print("[오류] 코드가 입력되지 않았습니다.")
        sys.exit(1)

    # code 추출
    code = redirected_input
    if "code=" in redirected_input:
        parsed = urllib.parse.urlparse(redirected_input)
        query = urllib.parse.parse_qs(parsed.query)
        code = query.get("code", [""])[0]

    if not code:
        print("[오류] URL에서 code 값을 추출하지 못했습니다.")
        sys.exit(1)

    print(f"\n[확인] 인가 코드(code) 획득: {code[:10]}...")
    print("Cafe24에 Access Token 발급 요청 중...")

    # Step 2: Access Token 교환 요청 (code_verifier 전달)
    token_url = f"https://{mall_id}.cafe24api.com/api/v2/oauth/token"
    basic_auth = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()

    token_payload = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
        "code_verifier": code_verifier,
    }
    token_data = urllib.parse.urlencode(token_payload).encode("utf-8")

    req = urllib.request.Request(token_url, data=token_data, method="POST")
    req.add_header("Authorization", f"Basic {basic_auth}")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")

    ctx = ssl.create_default_context()

    try:
        with urllib.request.urlopen(req, context=ctx) as response:
            res_body = response.read().decode("utf-8")
            res_json = json.loads(res_body)
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        print(f"\n[토큰 발급 실패: HTTP {e.code}]")
        print(err_body)
        sys.exit(1)
    except Exception as e:
        print(f"\n[오류 발생]: {e}")
        sys.exit(1)

    access_token = res_json.get("access_token")
    refresh_token = res_json.get("refresh_token")
    expires_at = res_json.get("expires_at")

    print("\n🎉 Access Token 발급 성공!")
    print(f"• 만료 시간: {expires_at}")
    print(f"• Access Token (일부): {access_token[:15]}...")

    # Step 3: 상품 목록 1건 조회 API 테스트
    print("\n[테스트] Cafe24 상품 API 조회 시도...")
    test_url = f"https://{mall_id}.cafe24api.com/api/v2/admin/products?limit=1"
    test_req = urllib.request.Request(test_url, method="GET")
    test_req.add_header("Authorization", f"Bearer {access_token}")
    test_req.add_header("Content-Type", "application/json")
    test_req.add_header("X-Cafe24-Api-Version", "2024-06-01")

    try:
        with urllib.request.urlopen(test_req, context=ctx) as test_res:
            product_data = json.loads(test_res.read().decode("utf-8"))
            products = product_data.get("products", [])
            print(f"✅ 상품 API 호출 성공! (조회된 상품 수: {len(products)}개)")
            if products:
                sample = products[0]
                print(f"   - 상품 번호: {sample.get('product_no')}")
                print(f"   - 상품명: {sample.get('product_name')}")
                print(f"   - 판매가: {sample.get('price')}원")
    except Exception as e:
        print(f"⚠️ 상품 API 호출 테스트 중 확인 필요: {e}")

    # Step 4: .env에 저장
    updates = {
        "Redirect_URI": redirect_uri,
        "CAFE24_ACCESS_TOKEN": access_token,
        "CAFE24_REFRESH_TOKEN": refresh_token,
        "CAFE24_EXPIRES_AT": expires_at,
    }
    update_env(ENV_PATH, updates)
    print(f"\n💾 .env 파일에 토큰 정보가 안전하게 업데이트되었습니다.")
    print("=" * 60)

if __name__ == "__main__":
    main()

