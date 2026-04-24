# 충암중 SWPBS 일일 자기점검 앱

충암중학교 학생들의 일일 행동 자기점검을 위한 웹 애플리케이션입니다.

## 기능

- 📝 **일일 자기점검**: 학생들이 매일 종례 후 5분 동안 자신의 행동을 점검
- 🎯 **MRS 규칙 기반**: 
  - 수업 3끝 (입실끝, 준비끝, 수행끝)
  - 교실 MRS (예의, 책임, 안전)
  - 복도·계단 MRS
  - 급식실 MRS
  - 화장실 MRS
- 📊 **결과 분석**: 실천율 계산 및 등급 평가 (매우 잘함, 잘함, 보통, 노력 필요)
- 📤 **Google Apps Script 연동**: 자동으로 Google Sheet에 데이터 저장

## 배포

이 프로젝트는 **Netlify**를 통해 자동으로 배포됩니다.

**배포 URL**: `your-netlify-site.netlify.app`

### 배포 방법

1. Netlify 계정에서 새 사이트 생성
2. GitHub 저장소 연결: `https://github.com/CDragon-G/chungam-swpbs-app`
3. Build command 설정: (비워두기 - 정적 파일)
4. Publish directory: `.` 또는 루트
5. Deploy 버튼 클릭

## 설정

`index.html`의 CONFIG 섹션에서 다음을 수정할 수 있습니다:

```javascript
const SCRIPT_URL = 'YOUR_APPS_SCRIPT_URL_HERE';
const CATS = [ /* 규칙 데이터 */ ];
```

### Google Apps Script 설정 (선택사항)

데이터를 Google Sheet에 저장하려면:

1. Google Apps Script 프로젝트 생성
2. 배포 가능한 앱(Apps Script API) 설정
3. 배포 URL을 `SCRIPT_URL` 변수에 입력

## 개발

```bash
# 저장소 클론
git clone https://github.com/CDragon-G/chungam-swpbs-app.git

# 변경 후 commit & push
git add .
git commit -m "메시지"
git push
```

변경사항은 자동으로 Netlify에 배포됩니다.

## 담당

- 충암중학교 인성생활부 신창용 교사

## 라이선스

학교 내부 사용 전용
