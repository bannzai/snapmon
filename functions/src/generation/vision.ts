// Cloud Vision の SafeSearch・Face Detection・Label Detection を 1 リクエストで実行し、生成してよい写真かを決める
// (documents/adr/0001-tech-stack.md「不適切な画像・人物」)。
// API: https://cloud.google.com/vision/docs/reference/rest/v1/images/annotate

const VISION_ENDPOINT = "https://vision.googleapis.com/v1/images:annotate";

/** 受け取るラベルの数。物の分類の state に入れるため、主なものだけで足りる。 */
const LABEL_MAXIMUM_RESULTS = 10;

/** SafeSearch の尤度。 */
type Likelihood = "UNKNOWN" | "VERY_UNLIKELY" | "UNLIKELY" | "POSSIBLE" | "LIKELY" | "VERY_LIKELY";

/** images:annotate の応答のうち、使う部分。 */
export interface VisionAnnotation {
  /** SafeSearch の判定。 */
  safeSearchAnnotation?: { adult?: Likelihood; violence?: Likelihood; racy?: Likelihood; medical?: Likelihood; spoof?: Likelihood };
  /** 検出した顔。 */
  faceAnnotations?: { detectionConfidence?: number }[];
  /** 画像のラベル。 */
  labelAnnotations?: { description: string; score: number }[];
  /** 画像単位のエラー。 */
  error?: { code: number; message: string };
}

/** Cloud Vision を呼ぶ関数。テストではモックに差し替える。 */
export type AnnotateImage = (image: Buffer) => Promise<VisionAnnotation>;

/** Cloud Vision を呼ぶ関数を作る。認証は実行サービスアカウントのアクセストークン。 */
export function createAnnotateImage({
  getAccessToken,
  fetchFunction,
}: {
  getAccessToken: () => Promise<string>;
  fetchFunction: typeof fetch;
}): AnnotateImage {
  return async (image) => {
    const response = await fetchFunction(VISION_ENDPOINT, {
      method: "POST",
      headers: { Authorization: `Bearer ${await getAccessToken()}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        requests: [
          {
            image: { content: image.toString("base64") },
            features: [
              { type: "SAFE_SEARCH_DETECTION" },
              { type: "FACE_DETECTION" },
              { type: "LABEL_DETECTION", maxResults: LABEL_MAXIMUM_RESULTS },
            ],
          },
        ],
      }),
    });
    if (!response.ok) {
      throw new Error(`Cloud Vision が HTTP ${response.status} を返しました: ${await response.text()}`);
    }
    const annotation = ((await response.json()) as { responses: VisionAnnotation[] }).responses[0];
    if (annotation.error) {
      throw new Error(`Cloud Vision が画像を読めませんでした: ${annotation.error.message}`);
    }
    return annotation;
  };
}

/** 生成しない理由。クライアントは理由ごとに案内を出し分ける。 */
export type RejectionReason =
  | "explicit_content"
  | "face_detected"
  | "person_detected"
  | "inappropriate_text"
  | "refused";

/**
 * 拒否とみなす SafeSearch の尤度。LIKELY までは通す (着ぐるみのイラストが LIKELY で拒否された誤検知を受け、owner が VERY_LIKELY だけに
 * 緩めた。https://github.com/bannzai/snapmon/issues/118 )。
 */
const REJECTED_LIKELIHOODS: Likelihood[] = ["VERY_LIKELY"];

/** Vision の判定から、生成しない理由を返す。生成してよければ undefined。顔は確信度を問わず 1 つでもあれば拒否する (人物の写真から作らないため)。 */
export function visionRejectionReason(annotation: VisionAnnotation): RejectionReason | undefined {
  const safeSearch = annotation.safeSearchAnnotation ?? {};
  if ([safeSearch.adult, safeSearch.violence, safeSearch.racy].some((likelihood) => likelihood && REJECTED_LIKELIHOODS.includes(likelihood))) {
    return "explicit_content";
  }
  if ((annotation.faceAnnotations ?? []).length > 0) {
    return "face_detected";
  }
  return undefined;
}

/** 拒否の内訳としてログに残す Vision の判定結果 (SafeSearch の各区分の尤度と、検出した顔の数・確信度)。写真の中身は含めない。 */
export function visionRejectionLogFields(annotation: VisionAnnotation) {
  return {
    safeSearch: annotation.safeSearchAnnotation ?? {},
    faceCount: (annotation.faceAnnotations ?? []).length,
    faceDetectionConfidences: (annotation.faceAnnotations ?? []).map((face) => face.detectionConfidence),
  };
}
