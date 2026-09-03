import Accelerate
import Foundation
import simd

/// Configuration for ICP registration.
struct ICPConfig {
    /// Maximum number of iterations.
    var maxIterations: Int = 50
    /// Convergence threshold: stop when mean error reduction is below this.
    var tolerance: Double = 1e-6
    /// Distance threshold for valid correspondences.
    var distanceThreshold: Double = 0.1
    /// Sample size for stochastic variants (0 = use all points).
    var sampleSize: Int = 0
}

/// Result of ICP registration.
struct ICPRegistrationResult {
    let transformed: PointCloud
    let transform: (rotation: simd_double3x3, translation: simd_double3)
    let meanError: Double
    let iterations: Int
    let converged: Bool
}

/// PointCloudMerger provides utilities for merging multiple point clouds
/// using ICP (Iterative Closest Point) registration to align consecutive
/// frames into a single global coordinate system.
enum PointCloudMerger {

    /// Default ICP configuration.
    static var icpConfig = ICPConfig()

    /// Merge a sequence of point clouds by aligning each frame to the previous
    /// one using ICP registration. Falls back to centroid alignment if ICP
    /// fails, and to concatenation when fewer than two clouds are provided.
    static func mergeConsecutive(_ clouds: [PointCloud], useICP: Bool = true) throws -> PointCloud {
        guard !clouds.isEmpty else {
            return PointCloud(points: [])
        }

        if clouds.count == 1 {
            return clouds[0]
        }

        var result = clouds[0]

        for i in 1..<clouds.count {
            let next = clouds[i]
            let aligned: PointCloud

            if useICP {
                // First align centroids as ICP needs reasonably close initial poses
                let centroidAligned = alignToReference(cloud: next, reference: result)
                if let icpResult = runICP(source: centroidAligned, target: result) {
                    aligned = icpResult.transformed
                } else {
                    // ICP failed, fall back to centroid alignment
                    aligned = centroidAligned
                }
            } else {
                aligned = alignToReference(cloud: next, reference: result)
            }

            result.points.append(contentsOf: aligned.points)
        }

        return result
    }

    // MARK: - ICP Registration

    /// Run ICP to align source cloud to target. Returns nil if ICP fails.
    private static func runICP(source: PointCloud, target: PointCloud) -> ICPRegistrationResult? {
        guard !source.points.isEmpty && !target.points.isEmpty else { return nil }

        // Build k-d tree for target for efficient nearest neighbor search
        let kdTree = KDTree(points: target.points.map { simd_double3($0.x, $0.y, $0.z) })

        var currentCloud = source
        var prevError = Double.infinity
        var converged = false
        var finalIterations = 0
        var totalTransform = simd_double3x3(diagonal: simd_double3(1, 1, 1))
        var totalTranslation = simd_double3(0, 0, 0)

        for iteration in 0..<icpConfig.maxIterations {
            finalIterations = iteration + 1

            // Find correspondences
            var correspondences: [(source: simd_double3, target: simd_double3)] = []
            var totalError = 0.0

            let sample: [PointCloud.Point]
            if icpConfig.sampleSize > 0 && currentCloud.points.count > icpConfig.sampleSize {
                sample = Array(currentCloud.points.shuffled().prefix(icpConfig.sampleSize))
            } else {
                sample = currentCloud.points
            }

            for pt in sample {
                let srcPt = simd_double3(pt.x, pt.y, pt.z)
                if let (nearest, distance) = kdTree.nearest(to: srcPt) {
                    if distance < icpConfig.distanceThreshold {
                        correspondences.append((source: srcPt, target: nearest))
                        totalError += distance * distance
                    }
                }
            }

            guard !correspondences.isEmpty else { break }

            let meanError = totalError / Double(correspondences.count)

            // Check convergence
            if prevError - meanError < icpConfig.tolerance {
                converged = true
                break
            }
            prevError = meanError

            // Compute optimal transformation using SVD
            if let (rotation, translation) = computeRigidTransform(correspondences) {
                // Apply transformation
                currentCloud = transformCloud(currentCloud, rotation: rotation, translation: translation)
                totalTransform = rotation * totalTransform
                totalTranslation = rotation * totalTranslation + translation
            } else {
                break
            }
        }

        return ICPRegistrationResult(
            transformed: currentCloud,
            transform: (rotation: totalTransform, translation: totalTranslation),
            meanError: prevError,
            iterations: finalIterations,
            converged: converged
        )
    }

    /// Compute optimal rigid transformation (R + t) using SVD.
    private static func computeRigidTransform(
        _ correspondences: [(source: simd_double3, target: simd_double3)]
    ) -> (rotation: simd_double3x3, translation: simd_double3)? {

        let n = Double(correspondences.count)

        // Compute centroids
        var srcCentroid = simd_double3(0, 0, 0)
        var tgtCentroid = simd_double3(0, 0, 0)

        for c in correspondences {
            srcCentroid += c.source
            tgtCentroid += c.target
        }
        srcCentroid /= n
        tgtCentroid /= n

        // Compute cross-covariance matrix H
        var H = simd_double3x3(0)
        for c in correspondences {
            let srcCentered = c.source - srcCentroid
            let tgtCentered = c.target - tgtCentroid
            H += simd_cross(tgtCentered, srcCentered).skewSymmetric
        }

        // SVD decomposition for optimal rotation
        // Using the Procrustes problem solution: R = V * U^T
        let Ht = H.transpose
        let svdResult = svd3x3(H + Ht)

        // Ensure proper rotation (det(R) = 1)
        var R = svdResult.V.transpose * svdResult.U.transpose
        if R.determinant < 0 {
            let correction = simd_double3x3(diagonal: simd_double3(1, 1, -1))
            R = svdResult.V.transpose * correction * svdResult.U.transpose
        }

        let t = tgtCentroid - R * srcCentroid

        return (rotation: R, translation: t)
    }

    /// Apply rigid transformation to a point cloud.
    private static func transformCloud(
        _ cloud: PointCloud,
        rotation: simd_double3x3,
        translation: simd_double3
    ) -> PointCloud {
        let transformedPoints = cloud.points.map { pt -> PointCloud.Point in
            let p = simd_double3(pt.x, pt.y, pt.z)
            let transformed = rotation * p + translation
            return PointCloud.Point(
                x: transformed.x,
                y: transformed.y,
                z: transformed.z,
                r: pt.r,
                g: pt.g,
                b: pt.b
            )
        }
        return PointCloud(points: transformedPoints)
    }

    // MARK: - Centroid alignment (fallback)

    /// Compute the centroid (average position) of a point cloud.
    private static func centroid(of cloud: PointCloud) -> (x: Double, y: Double, z: Double) {
        guard !cloud.points.isEmpty else { return (0, 0, 0) }
        let n = Double(cloud.points.count)
        let sx = cloud.points.reduce(0.0) { $0 + $1.x }
        let sy = cloud.points.reduce(0.0) { $0 + $1.y }
        let sz = cloud.points.reduce(0.0) { $0 + $1.z }
        return (sx / n, sy / n, sz / n)
    }

    /// Align `cloud` to `reference` by translating so their centroids coincide.
    /// This is the simplest viable registration: it removes translational offset
    /// between consecutive scan frames without attempting rotation correction.
    private static func alignToReference(cloud: PointCloud, reference: PointCloud) -> PointCloud {
        let refCentroid = centroid(of: reference)
        let srcCentroid = centroid(of: cloud)

        let dx = refCentroid.x - srcCentroid.x
        let dy = refCentroid.y - srcCentroid.y
        let dz = refCentroid.z - srcCentroid.z

        let alignedPoints = cloud.points.map { pt -> PointCloud.Point in
            PointCloud.Point(
                x: pt.x + dx,
                y: pt.y + dy,
                z: pt.z + dz,
                r: pt.r,
                g: pt.g,
                b: pt.b
            )
        }

        return PointCloud(points: alignedPoints)
    }
}

// MARK: - KD-Tree for nearest neighbor search

/// Simple k-d tree for 3D point nearest neighbor queries.
private struct KDTree {
    struct Node {
        let point: simd_double3
        let axis: Int
        let left: Int?
        let right: Int?
    }

    let nodes: [Node]

    init(points: [simd_double3]) {
        self.nodes = KDTree.build(points: points, depth: 0)
    }

    private static func build(points: [simd_double3], depth: Int) -> [Node] {
        guard !points.isEmpty else { return [] }

        let axis = depth % 3
        let sorted = points.sorted { $0[axis] < $1[axis] }
        let median = sorted.count / 2

        var nodes: [Node] = []
        let currentIndex = nodes.count

        let leftPoints = Array(sorted[..<median])
        let rightPoints = Array(sorted[(median + 1)...])

        let leftNodes = build(points: leftPoints, depth: depth + 1)
        let rightNodes = build(points: rightPoints, depth: depth + 1)

        let leftIndex = leftNodes.isEmpty ? nil : currentIndex + 1
        let rightIndex = rightNodes.isEmpty ? nil : currentIndex + 1 + leftNodes.count

        nodes.append(Node(
            point: sorted[median],
            axis: axis,
            left: leftIndex,
            right: rightIndex
        ))
        nodes.append(contentsOf: leftNodes)
        nodes.append(contentsOf: rightNodes)

        return nodes
    }

    /// Find nearest point to query within threshold distance.
    func nearest(to query: simd_double3) -> (point: simd_double3, distance: Double)? {
        return nearestRecursive(nodeIndex: 0, query: query, best: nil)
    }

    private func nearestRecursive(
        nodeIndex: Int,
        query: simd_double3,
        best: (point: simd_double3, distance: Double)?
    ) -> (point: simd_double3, distance: Double)? {
        guard nodeIndex < nodes.count else { return best }

        let node = nodes[nodeIndex]
        let dist = simd_distance(query, node.point)

        var currentBest = best
        if currentBest == nil || dist < currentBest!.distance {
            currentBest = (point: node.point, distance: dist)
        }

        let diff = query[node.axis] - node.point[node.axis]
        let nearNode = diff < 0 ? node.left : node.right
        let farNode = diff < 0 ? node.right : node.left

        // Search near side first
        if let nearIdx = nearNode {
            currentBest = nearestRecursive(nodeIndex: nearIdx, query: query, best: currentBest)
        }

        // Check if far side could contain a closer point
        if let farIdx = farNode {
            if currentBest == nil || abs(diff) < currentBest!.distance {
                currentBest = nearestRecursive(nodeIndex: farIdx, query: query, best: currentBest)
            }
        }

        return currentBest
    }
}

// MARK: - SIMD Extensions

private extension simd_double3 {
    var skewSymmetric: simd_double3x3 {
        simd_double3x3(
            simd_double3(0, -self.z, self.y),
            simd_double3(self.z, 0, -self.x),
            simd_double3(-self.y, self.x, 0)
        )
    }
}

private func svd3x3(_ A: simd_double3x3) -> (U: simd_double3x3, S: simd_double3, V: simd_double3x3) {
    // Simplified SVD for 3x3 using power iteration with deflation
    // For full robustness, consider using a proper LAPACK binding
    var U = simd_double3x3(diagonal: simd_double3(1, 1, 1))
    var V = simd_double3x3(diagonal: simd_double3(1, 1, 1))
    var S = simd_double3(
        simd_length(A.columns.0),
        simd_length(A.columns.1),
        simd_length(A.columns.2)
    )

    // Power iteration (simplified)
    let maxIter = 20
    for _ in 0..<maxIter {
        // Approximate singular vectors
        let v0 = simd_normalize(A * A.columns.0)
        let v1 = simd_normalize(A * A.columns.1)
        let v2 = simd_normalize(A * A.columns.2)

        V = simd_double3x3(columns: (v0, v1, v2))

        let AV = A * V
        U = simd_double3x3(
            columns: (
                simd_normalize(AV.columns.0),
                simd_normalize(AV.columns.1),
                simd_normalize(AV.columns.2)
            )
        )

        S = simd_double3(
            simd_length(AV.columns.0),
            simd_length(AV.columns.1),
            simd_length(AV.columns.2)
        )
    }

    return (U, S, V)
}
