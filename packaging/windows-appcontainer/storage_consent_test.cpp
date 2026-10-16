#include "storage_consent.h"

#include <cassert>
#include <iostream>

using namespace gami::storage;

location_classification value(location_kind kind, std::uint64_t id) {
    return {kind, L"test", L"X:\\test", {1, 0, id}};
}

int main() {
    auto local_source = value(location_kind::local, 1);
    auto local_destination = value(location_kind::local, 2);
    assert(!requires_explicit_consent(local_source, local_destination));
    auto local = authorize_storage(local_source, local_destination, false);
    validate_authorization(local, local_source, local_destination);

    auto local_became_remote = local_source;
    local_became_remote.kind = location_kind::network_cloud;
    bool rejected{};
    try { validate_authorization(local, local_became_remote, local_destination); }
    catch (identity_error const&) { rejected = true; }
    assert(rejected);

    for (auto kind : {location_kind::network_cloud, location_kind::unknown}) {
        auto remote = value(kind, 3);
        assert(requires_explicit_consent(remote, local_destination));
        bool denied{};
        try { (void)authorize_storage(remote, local_destination, false); }
        catch (identity_error const&) { denied = true; }
        assert(denied);
        auto approved = authorize_storage(remote, local_destination, true);
        validate_authorization(approved, remote, local_destination);

        auto substituted = remote;
        substituted.identity.file_id_low++;
        rejected = false;
        try { validate_authorization(approved, substituted, local_destination); }
        catch (identity_error const&) { rejected = true; }
        assert(rejected);

        auto substituted_destination = local_destination;
        substituted_destination.identity.file_id_low++;
        rejected = false;
        try { validate_authorization(approved, remote, substituted_destination); }
        catch (identity_error const&) { rejected = true; }
        assert(rejected);

        auto reclassified = remote;
        reclassified.kind = location_kind::local;
        rejected = false;
        try { validate_authorization(approved, reclassified, local_destination); }
        catch (identity_error const&) { rejected = true; }
        assert(rejected);
    }

    // A resume must not inherit approval after either selected identity is
    // remapped or its material location classification changes.
    auto remote_source = value(location_kind::network_cloud, 10);
    auto remote_destination = value(location_kind::network_cloud, 11);
    auto resume_approval = authorize_storage(remote_source, remote_destination, true);
    auto remapped_destination = remote_destination;
    remapped_destination.identity.file_id_low = 12;
    bool resume_rejected{};
    try { validate_authorization(resume_approval, remote_source, remapped_destination); }
    catch (identity_error const&) { resume_rejected = true; }
    assert(resume_rejected);

    auto uncertain_destination = remote_destination;
    uncertain_destination.kind = location_kind::unknown;
    resume_rejected = false;
    try { validate_authorization(resume_approval, remote_source, uncertain_destination); }
    catch (identity_error const&) { resume_rejected = true; }
    assert(resume_rejected);

    std::cout << "storage consent policy tests passed\n";
}
