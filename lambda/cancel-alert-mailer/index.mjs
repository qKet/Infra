import { SESv2Client, SendEmailCommand } from "@aws-sdk/client-sesv2";

// NOTI01_ALERT01(공연 취소표 알림) — backend(NotificationServiceImpl.publishCancelAlerts)가 구독자 1명당
// SQS 메시지 1건을 publish하면, 여기서 그 메시지를 SES SendEmail로 바꿔서 보낸다.
// FROM_EMAIL은 SES에서 verify된 도메인(jun979.click) 소속이어야 함 — modules/lambda 환경변수로 주입됨.
const REGION = process.env.AWS_REGION;
const FROM_EMAIL = process.env.FROM_EMAIL;

const ses = new SESv2Client({ region: REGION });

export const handler = async (event) => {
  const results = await Promise.allSettled(event.Records.map(sendCancelAlertEmail));

  // partial batch failure: 실패한 record의 messageId만 돌려주면 SQS가 그 건만 다시 보내줌
  // (event source mapping에 function_response_types=["ReportBatchItemFailures"] 설정돼 있어야 동작)
  const batchItemFailures = [];
  results.forEach((result, i) => {
    if (result.status === "rejected") {
      console.error("취소표 알림 발송 실패", event.Records[i].messageId, result.reason);
      batchItemFailures.push({ itemIdentifier: event.Records[i].messageId });
    }
  });

  return { batchItemFailures };
};

async function sendCancelAlertEmail(record) {
  const { toEmail, pTitle, venueName, roundTime } = JSON.parse(record.body);

  if (!toEmail) {
    throw new Error(`toEmail이 없는 메시지 (messageId=${record.messageId})`);
  }

  const subject = `[qKet] "${pTitle}" 취소표가 발생했습니다`;
  const body =
    `${pTitle} (${venueName})\n` +
    `공연 일시: ${formatRoundTime(roundTime)}\n\n` +
    `구독하신 회차에 취소표가 발생했습니다. 서두르지 않으면 놓칠 수 있어요!\n` +
    `지금 바로 qKet에서 예매해보세요.`;

  await ses.send(
    new SendEmailCommand({
      FromEmailAddress: FROM_EMAIL,
      Destination: { ToAddresses: [toEmail] },
      Content: {
        Simple: {
          Subject: { Data: subject, Charset: "UTF-8" },
          Body: { Text: { Data: body, Charset: "UTF-8" } },
        },
      },
    })
  );
}

// 백엔드가 LocalDateTime을 그대로 Jackson 직렬화해서 보내므로 "2026-08-15T19:00:00" 형태로 옴
function formatRoundTime(iso) {
  if (!iso) return "";
  const [date, time] = iso.split("T");
  return time ? `${date} ${time.slice(0, 5)}` : date;
}
