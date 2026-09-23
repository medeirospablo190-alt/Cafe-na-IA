#include "cafeina/LuauRuntime.hpp"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <string>
#include <thread>

namespace {

namespace fs = std::filesystem;

void require(bool condition, const char* message)
{
    if (!condition)
    {
        std::cerr << "FAIL: " << message << "\n";
        std::exit(1);
    }
}

fs::path makeTempRoot()
{
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    fs::path root = fs::temp_directory_path() / ("cafeina-runtime-fs-" + std::to_string(stamp));
    std::error_code ec;
    fs::remove_all(root, ec);
    fs::create_directories(root);
    return root;
}

} // namespace

int main()
{
    cafeina::LuauRuntime runtime;

    {
        const auto r = runtime.execute("print('hello', 42) return 2 + 3", {250});
        require(r.ok, "basic script should succeed");
        require(r.output == "hello\t42\n", "print should be captured");
        require(r.returns.size() == 1 && r.returns[0] == "5", "return value should be captured");
    }

    {
        cafeina::ExecutionRequest request;
        request.source = "return 6 * 7";
        request.limits.timeoutMs = 250;
        request.context.executionId = "smoke-execution-1";
        request.context.projectId = "smoke-project";

        const cafeina::ExecutionResult r = runtime.execute(request);
        require(r.ok, "canonical execution request should succeed");
        require(
            r.returns.size() == 1 && r.returns[0] == "42",
            "canonical execution request should capture return values"
        );
    }

    {
        cafeina::ExecutionRequest request;
        request.source = "return true";
        request.context.capabilities.grant(cafeina::RuntimeCapability::Files);

        const auto r = runtime.execute(request);
        require(!r.ok, "FILES capability without a sandbox root should fail closed");
        require(
            r.error.find("FILES capability requires") != std::string::npos,
            "missing FILES host access should have an explicit error"
        );
    }

    {
        const auto r = runtime.execute("return fs == nil", {250});
        require(r.ok, "runtime without host files should still execute");
        require(r.returns.size() == 1 && r.returns[0] == "true", "fs should not exist without explicit host access");
    }

    {
        const auto r = runtime.execute("return World == nil", {250});
        require(r.ok, "runtime without WORLD capability should still execute");
        require(
            r.returns.size() == 1 && r.returns[0] == "true",
            "World should not exist without explicit capability"
        );
    }

    {
        cafeina::ExecutionRequest request;
        request.source = "return true";
        request.context.capabilities.grant(cafeina::RuntimeCapability::World);

        const auto r = runtime.execute(request);
        require(!r.ok, "WORLD capability without WorldService should fail closed");
        require(
            r.error.find("WORLD capability requires") != std::string::npos,
            "missing WorldService should have an explicit error"
        );
    }

    {
        cafeina::world::WorldService sharedWorld;

        cafeina::RuntimeHostAccess deniedHost;
        deniedHost.worldService = &sharedWorld;

        cafeina::ExecutionRequest deniedRequest;
        deniedRequest.source = "return World == nil";
        deniedRequest.context.hostAccess = deniedHost;

        const auto denied = runtime.execute(deniedRequest);
        require(denied.ok, "WorldService host access without capability should remain valid");
        require(
            denied.returns.size() == 1 && denied.returns[0] == "true",
            "WorldService pointer alone must not expose World API"
        );
        require(sharedWorld.objectCount() == 0, "denied World access must not mutate host scene");

        cafeina::ExecutionRequest request;
        request.source =
            "local house = World.create('House') "
            "local door = World.create('Door') "
            "assert(World.setParent(door, house)) "
            "assert(World.setPosition(house, 1, 2, 3)) "
            "assert(World.setRotation(house, 0, 45, 0)) "
            "assert(World.setScale(house, 2, 2, 2)) "
            "local object = World.get(house) "
            "local children = World.children(house) "
            "return house, door, object.name, object.position.x, "
            "object.rotationDegrees.y, object.scale.x, children[1]";
        request.limits.timeoutMs = 500;
        request.context.capabilities.grant(cafeina::RuntimeCapability::World);
        request.context.hostAccess.worldService = &sharedWorld;

        const auto r = runtime.execute(request);
        require(r.ok, "WORLD capability should expose the structured World API");
        require(r.returns.size() == 7, "World script should return seven verification values");
        require(r.returns[0] == "1" && r.returns[1] == "2", "World IDs should be stable decimal strings");
        require(r.returns[2] == "House", "World.get should return object name");
        require(r.returns[3] == "1", "World.setPosition should update position");
        require(r.returns[4] == "45", "World.setRotation should update rotation");
        require(r.returns[5] == "2", "World.setScale should update scale");
        require(r.returns[6] == "2", "World.children should return child IDs as strings");

        require(sharedWorld.objectCount() == 2, "Luau World API should mutate the shared host scene");

        const auto house = sharedWorld.object(1);
        const auto door = sharedWorld.object(2);
        require(house.has_value() && house->name == "House", "host should observe Luau-created house");
        require(door.has_value() && door->parentId == 1, "host should observe Luau-created hierarchy");
        require(house->transform.position.x == 1.0, "host should observe Luau transform changes");

        cafeina::ExecutionRequest partRequest;
        partRequest.source = "local part = World.createPart('RenderBox') return part";
        partRequest.context.capabilities.grant(cafeina::RuntimeCapability::World);
        partRequest.context.hostAccess.worldService = &sharedWorld;

        const auto partResult = runtime.execute(partRequest);
        require(partResult.ok, "World.createPart should create a renderable object");
        require(
            partResult.returns.size() == 1 && partResult.returns[0] == "3",
            "World.createPart should preserve stable object IDs"
        );

        const auto partMesh = sharedWorld.meshComponent(3);
        require(partMesh.has_value(), "World.createPart should attach a mesh component");
        require(
            partMesh->primitive == cafeina::world::PrimitiveMesh::Box && partMesh->visible,
            "World.createPart should attach a visible box mesh"
        );
    }

    {
        const auto r = runtime.execute("local =", {250});
        require(!r.ok, "syntax error should fail");
        require(!r.error.empty(), "syntax error should have a message");
    }

    {
        const auto r = runtime.execute("error('boom')", {250});
        require(!r.ok, "runtime error should fail");
        require(r.error.find("boom") != std::string::npos, "runtime error should contain message");
    }

    {
        const auto r = runtime.execute("while true do end", {40});
        require(!r.ok, "infinite loop should be interrupted");
        require(r.error.find("timed out") != std::string::npos, "timeout should be reported");
    }

    {
        auto cancellation = std::make_shared<cafeina::CancellationToken>();
        cancellation->cancel();

        cafeina::ExecutionRequest request;
        request.source = "return 1";
        request.limits.timeoutMs = 500;
        request.context.cancellation = cancellation;

        const auto r = runtime.execute(request);
        require(!r.ok, "pre-cancelled execution should not start");
        require(
            r.error.find("cancelled") != std::string::npos,
            "pre-cancelled execution should report cancellation"
        );
    }

    {
        auto cancellation = std::make_shared<cafeina::CancellationToken>();

        cafeina::ExecutionRequest request;
        request.source = "while true do end";
        request.limits.timeoutMs = 2000;
        request.context.cancellation = cancellation;

        cafeina::RuntimeResult r;
        std::thread worker([&]() {
            cafeina::LuauRuntime cancellableRuntime;
            r = cancellableRuntime.execute(request);
        });

        std::this_thread::sleep_for(std::chrono::milliseconds(25));
        cancellation->cancel();
        worker.join();

        require(!r.ok, "running execution should stop after cancellation");
        require(
            r.error.find("cancelled") != std::string::npos,
            "running execution should report cancellation instead of timeout"
        );
    }

    const fs::path root = makeTempRoot();
    cafeina::RuntimeHostAccess host;
    host.filesRoot = root.string();

    {
        const fs::path requestRoot = makeTempRoot();
        cafeina::RuntimeHostAccess requestHost;
        requestHost.filesRoot = requestRoot.string();

        cafeina::ExecutionRequest deniedRequest;
        deniedRequest.source = "return fs == nil";
        deniedRequest.context.hostAccess = requestHost;

        const auto denied = runtime.execute(deniedRequest);
        require(denied.ok, "host access without capability should remain a valid execution");
        require(
            denied.returns.size() == 1 && denied.returns[0] == "true",
            "host access alone must not expose filesystem API"
        );

        cafeina::ExecutionRequest request;
        request.source =
            "fs.write('request.txt', 'context-ok') "
            "return fs.read('request.txt')";
        request.limits.timeoutMs = 500;
        request.context.executionId = "smoke-execution-files";
        request.context.projectId = "smoke-project";
        request.context.capabilities.grant(cafeina::RuntimeCapability::Files);
        request.context.hostAccess = requestHost;

        const auto r = runtime.execute(request);
        require(r.ok, "execution request should carry explicit host access");
        require(
            r.returns.size() == 1 && r.returns[0] == "context-ok",
            "execution request host access should expose the same sandboxed fs API"
        );
        require(
            fs::is_regular_file(requestRoot / "request.txt"),
            "execution request filesystem must remain inside its sandbox root"
        );

        std::error_code requestCleanup;
        fs::remove_all(requestRoot, requestCleanup);
    }

    {
        const auto r = runtime.execute(
            "fs.write('note.txt', 'hello') "
            "fs.write('b.txt', 'two') "
            "local files = fs.list() "
            "return fs.read('note.txt'), fs.exists('note.txt'), table.concat(files, ',')",
            {500},
            host
        );

        require(r.ok, "sandboxed filesystem operations should succeed");
        require(r.returns.size() == 3, "filesystem script should return three values");
        require(r.returns[0] == "hello", "fs.read should return saved content");
        require(r.returns[1] == "true", "fs.exists should report saved file");
        require(r.returns[2] == "b.txt,note.txt", "fs.list should be sorted and sandbox-scoped");
        require(fs::is_regular_file(root / "note.txt"), "runtime file should exist inside sandbox root");
        require(!fs::exists(root.parent_path() / "note.txt"), "runtime file must not escape sandbox root");
    }

    {
        const auto r = runtime.execute(
            "fs.write('../escape.txt', 'bad')",
            {250},
            host
        );

        require(!r.ok, "path traversal should fail");
        require(
            r.error.find("invalid runtime file name") != std::string::npos,
            "path traversal should report invalid runtime file name"
        );
        require(!fs::exists(root.parent_path() / "escape.txt"), "path traversal must not create an outside file");
    }

    {
        const fs::path outside = root.parent_path() / "cafeina-runtime-outside.txt";
        {
            std::ofstream output(outside, std::ios::binary | std::ios::trunc);
            output << "outside";
        }

        std::error_code ec;
        fs::create_symlink(outside, root / "link.txt", ec);
        if (!ec)
        {
            const auto r = runtime.execute("return fs.read('link.txt')", {250}, host);
            require(!r.ok, "symlink reads should fail");
            require(
                r.error.find("symbolic links are not allowed") != std::string::npos,
                "symlink rejection should be explicit"
            );
        }

        fs::remove(outside, ec);
    }

    {
        const auto r = runtime.execute(
            "fs.write('persist.txt', 'saved') return fs.read('persist.txt')",
            {250},
            host
        );
        require(r.ok, "filesystem data should persist across executions");

        const auto reopened = runtime.execute("return fs.read('persist.txt')", {250}, host);
        require(reopened.ok, "subsequent execution should read persisted sandbox file");
        require(
            reopened.returns.size() == 1 && reopened.returns[0] == "saved",
            "sandbox file should persist between runtime executions"
        );
    }

    std::error_code cleanup;
    fs::remove_all(root, cleanup);

    std::cout << "runtime smoke tests passed\n";
    return 0;
}
